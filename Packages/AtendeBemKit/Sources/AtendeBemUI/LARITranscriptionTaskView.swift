import AtendeBemCore
import Foundation
import Observation
import SwiftUI
#if os(iOS)
import AVFoundation
import UIKit
#endif

@MainActor @Observable
final class LARIAudioTaskSession {
    enum Phase { case ready, requestingPermission, recording, audioReady, transcribing, review, expired }
    private enum PreparationStep {
        case checkingContext, microphonePermission, audioSession, protectedFile, recorder
        var message: String {
            switch self {
            case .checkingContext: "Conferindo a sessão e a clínica…"
            case .microphonePermission: "Aguardando autorização do microfone…"
            case .audioSession: "Preparando o microfone…"
            case .protectedFile, .recorder: "Preparando a gravação…"
            }
        }
    }
    private enum RecordingError: Error, LocalizedError {
        case unavailable
        var errorDescription: String? {
            "O aparelho não conseguiu iniciar a gravação. Encerre outras gravações ou chamadas e tente novamente. Você pode continuar anotando a consulta sem gravar."
        }
    }
    var patientConsent = false
    var aiConsent = false
    var transcript = ""
    private(set) var disclaimer = ""
    private(set) var seconds: Int = 0
    private(set) var phase = Phase.ready
    private(set) var error: String?
    private(set) var cleanupError: String?
    private(set) var needsMicrophoneSettings = false
    private var preparationStep: PreparationStep?
    private static var activeFolders = Set<URL>()
    private let api: APIClient
    private let context: UUID
    private let current: @MainActor () -> Bool
    @ObservationIgnored private var directory: URL?
    private var audioURL: URL?
    private var generation = UUID()
    private var ticker: Task<Void, Never>?
    private var processing: Task<Void, Never>?
    #if os(iOS)
    private var recorder: AVAudioRecorder?
    #endif
    var isWorking: Bool { [.requestingPermission, .recording, .transcribing].contains(phase) }
    var isContextCurrent: Bool { current() }
    var hasContent: Bool { audioURL != nil || !transcript.isEmpty }
    var canStart: Bool { phase == .ready && patientConsent && aiConsent && cleanupError == nil }
    var preparationMessage: String { preparationStep?.message ?? "Preparando a gravação…" }

    init(api: APIClient, context: UUID, isContextCurrent: @escaping @MainActor () -> Bool) {
        self.api = api; self.context = context; self.current = isContextCurrent
        cleanupOrphans()
    }

    deinit {
        // Files belong to this task even if its presenting chat is removed.
        // On failure the directory remains an orphan eligible for the next sweep.
        if let folder = directory {
            do { try FileManager.default.removeItem(at: folder) } catch { /* next task retries the owned orphan */ }
            Task { @MainActor in Self.activeFolders.remove(folder) }
        }
    }

    func start() async {
        guard canStart, current() else { return }
        cleanupOrphans()
        guard cleanupError == nil else { return }
        let operation = UUID(); generation = operation; phase = .requestingPermission; error = nil
        needsMicrophoneSettings = false; preparationStep = .checkingContext
        defer { if generation == operation { preparationStep = nil } }
        #if os(iOS)
        do {
            // This guard validates the session context, not service availability or plan eligibility.
            try await LARIAdvancedAccess.require(api: api, context: context)
            guard generation == operation else { return }
            guard current(), patientConsent, aiConsent else { invalidate(); return }
            preparationStep = .microphonePermission
            let permission = await AVAudioApplication.requestRecordPermission()
            guard generation == operation else { return }
            guard current(), patientConsent, aiConsent else { invalidate(); return }
            guard permission else {
                phase = .ready; needsMicrophoneSettings = true
                error = "Autorize o microfone nos Ajustes do aparelho para gravar. Você pode continuar anotando a consulta sem gravação."
                return
            }
            try Task.checkCancellation()
            preparationStep = .audioSession
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            preparationStep = .protectedFile
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AtendeBem-audio-\(UUID().uuidString)", isDirectory: true)
            directory = folder; Self.activeFolders.insert(folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
            var protectedFolder = folder
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try protectedFolder.setResourceValues(values)
            let file = folder.appendingPathComponent("consulta.m4a")
            preparationStep = .recorder
            let next = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ])
            audioURL = file; recorder = next
            guard next.prepareToRecord(), next.record(forDuration: 15 * 60) else { throw RecordingError.unavailable }
            // The file inherits complete protection from its private parent directory.
            preparationStep = .protectedFile
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600], ofItemAtPath: file.path)
            seconds = 0; phase = .recording
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard let self, self.phase == .recording else { return }
                    guard self.current() else { self.invalidate(); return }
                    self.seconds = Int(self.recorder?.currentTime ?? 0)
                    let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
                    if self.recorder?.isRecording != true || self.seconds >= 15 * 60 || bytes >= ConsultationAudioRequest.maximumBytes - 65_536 {
                        self.stopRecording(); return
                    }
                }
            }
        } catch {
            guard generation == operation else { return }
            stopHardware(); _ = removeAudio()
            guard current(), patientConsent, aiConsent else { invalidate(); return }
            phase = .ready
            self.error = error is CancellationError ? nil : preparationFailureMessage(for: error)
        }
        #else
        phase = .ready; error = "A gravação de consulta está disponível no aplicativo para iPhone e iPad."
        #endif
    }

    func stopRecording() {
        guard phase == .recording else { return }
        stopHardware(); phase = .audioReady
    }

    func transcribe() {
        guard phase == .audioReady, patientConsent, aiConsent, current(), let url = audioURL else { return }
        let operation = generation
        phase = .transcribing; error = nil
        processing = Task { [weak self] in
            guard let self else { return }
            do {
                try await LARIAdvancedAccess.require(api: self.api, context: self.context)
                guard self.generation == operation, self.current(), self.patientConsent, self.aiConsent else { self.invalidate(); return }
                let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                guard (48...ConsultationAudioRequest.maximumBytes).contains(size) else { throw LARIAdvancedError.invalidAudio }
                let data = try Data(contentsOf: url)
                let request = try ConsultationAudioRequest(data: data, mimeType: "audio/mp4", consent: true)
                guard self.removeAudio() else { self.phase = .audioReady; self.processing = nil; return }
                let result = try await self.api.transcribeAudio(request, expectedContext: self.context)
                guard self.generation == operation, self.current(), self.patientConsent, self.aiConsent else { self.invalidate(); return }
                self.transcript = result.texto; self.disclaimer = result.disclaimer; self.phase = .review
            } catch {
                guard self.generation == operation else { return }
                let removed = self.removeAudio()
                guard self.current() else { self.invalidate(); return }
                self.phase = .ready
                self.error = audioFailureMessage(for: error) + (removed
                    ? " O áudio local foi removido. Nenhuma anotação foi salva; grave novamente se desejar tentar outra vez."
                    : " A remoção do áudio local ainda não foi confirmada. Use Tentar excluir áudio antes de iniciar outra gravação.")
            }
            self.processing = nil
        }
    }

    @discardableResult func reset() -> Bool {
        generation = UUID(); processing?.cancel(); processing = nil
        stopHardware(); let removed = removeAudio()
        transcript = ""; disclaimer = ""; seconds = 0; error = nil; needsMicrophoneSettings = false; preparationStep = nil
        phase = removed ? .ready : .audioReady
        return removed
    }
    func invalidate() {
        reset(); patientConsent = false; aiConsent = false; phase = .expired
        // A failed cleanup remains eligible for a retry by the next task in this process.
        if let directory { Self.activeFolders.remove(directory) }
    }
    private func preparationFailureMessage(for error: Error) -> String {
        if error is APIError || error is URLError || error is LARIAdvancedError || error is RecordingError {
            return audioFailureMessage(for: error)
        }
        switch preparationStep {
        case .protectedFile:
            return "Não foi possível preparar o áudio temporário protegido neste aparelho. Confira se há espaço disponível e tente novamente. Você pode continuar anotando a consulta sem gravar."
        case .audioSession, .recorder:
            return RecordingError.unavailable.localizedDescription
        default:
            return "Não foi possível preparar a gravação. Confira sua conexão e tente novamente. Você pode continuar anotando a consulta sem gravar."
        }
    }
    private func audioFailureMessage(for error: Error) -> String {
        if let advanced = error as? LARIAdvancedError { return advanced.localizedDescription }
        if let recording = error as? RecordingError { return recording.localizedDescription }
        if error is CancellationError { return "A transcrição foi interrompida." }
        return message(for: error)
    }
    private func stopHardware() {
        ticker?.cancel(); ticker = nil
        #if os(iOS)
        if let recorder { seconds = max(seconds, Int(recorder.currentTime)); recorder.stop() }
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    private func removeAudio() -> Bool {
        guard let directory else { return cleanupError == nil }
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            Self.activeFolders.remove(directory); self.directory = nil; audioURL = nil; cleanupError = nil
            return true
        } catch {
            cleanupError = "Não foi possível confirmar a exclusão do áudio temporário. Ele permanece protegido neste aparelho; tente excluir novamente."
            return false
        }
    }
    func retryCleanup() {
        if removeAudio() { if phase != .expired { phase = .ready } }
        cleanupOrphans()
    }
    private func cleanupOrphans() {
        do {
            let temporary = FileManager.default.temporaryDirectory
            let entries = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            for url in entries where url.lastPathComponent.hasPrefix("AtendeBem-audio-") && !Self.activeFolders.contains(url) {
                let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isDirectory == true, info.isSymbolicLink != true else { continue }
                try FileManager.default.removeItem(at: url)
            }
            if directory == nil { cleanupError = nil }
        } catch {
            cleanupError = "Há áudio temporário de uma tarefa anterior cuja exclusão ainda não foi confirmada. Tente excluir novamente antes de gravar."
        }
    }
}

struct LARITranscriptionTaskView: View {
    let command: String
    private let existingSession: LARIAudioTaskSession?
    private let onSessionReady: ((LARIAudioTaskSession) -> Void)?
    private let workflow: ConsultationWorkflow?
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var session: LARIAudioTaskSession?
    @State private var baseline: ConsultationContent?
    @State private var sectionID = ""
    @State private var reviewed = false
    @State private var applied = false
    @State private var confirmDiscard = false
    @State private var confirmLeave = false
    @State private var applicationError: String?
    private var allowed: Bool { app.user.map(LARIAdvancedAccess.clinical) == true }
    init(command: String, session: LARIAudioTaskSession? = nil, onSessionReady: ((LARIAudioTaskSession) -> Void)? = nil, workflow: ConsultationWorkflow? = nil) {
        self.command = command; self.existingSession = session; self.onSessionReady = onSessionReady; self.workflow = workflow
    }
    var body: some View {
        Group {
            if !allowed { RestrictedState() }
            else if let session { content(session) }
            else { ProgressView("Preparando gravação…") }
        }
        .navigationTitle("Transcrever consulta").inlineTitle()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") { if session?.hasContent == true { confirmLeave = true } else { dismiss() } }.disabled(session?.isWorking == true)
            }
        }
        .interactiveDismissDisabled(session?.hasContent == true || session?.isWorking == true)
        .task { [app] in
            if let existingSession { session = existingSession; return }
            let context = app.contextID
            let apiContext = await app.api.requestContextID()
            guard context == app.contextID, allowed else { return }
            let created = LARIAudioTaskSession(api: app.api, context: apiContext, isContextCurrent: { [weak app] in
                guard let app else { return false }
                return context == app.contextID && app.user.map(LARIAdvancedAccess.clinical) == true
            })
            session = created; onSessionReady?(created); baseline = workflow?.content
        }
        .onChange(of: app.contextID) { _, _ in session?.invalidate(); baseline = nil }
        .onChange(of: allowed) { _, value in if !value { session?.invalidate(); baseline = nil } }
        .onChange(of: scenePhase) { _, value in if value != .active { session?.stopRecording() } }
        .onDisappear {
            if session?.isWorking == true { session?.invalidate() }
            if onSessionReady == nil { session?.invalidate() }
        }
        .confirmationDialog("Descartar o áudio e o texto desta tarefa?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Descartar e começar novamente", role: .destructive) { if session?.reset() == true { baseline = workflow?.content; sectionID = ""; reviewed = false; applied = false; applicationError = nil } }
            Button("Manter", role: .cancel) {}
        }
        .confirmationDialog("Fechar a transcrição?", isPresented: $confirmLeave, titleVisibility: .visible) {
            if onSessionReady != nil { Button("Continuar depois nesta conversa") { dismiss() } }
            Button("Descartar e fechar", role: .destructive) { if session?.reset() == true { session?.patientConsent = false; session?.aiConsent = false; dismiss() } }
            Button("Continuar revisando", role: .cancel) {}
        } message: {
            Text(onSessionReady == nil ? "O texto ainda não aplicado será descartado ao fechar. Nenhuma anotação foi salva automaticamente."
                 : "A tarefa fica somente nesta sessão da conversa. Sair da conta, trocar de clínica ou encerrar o aplicativo descarta o conteúdo local.")
        }
    }

    private func content(_ session: LARIAudioTaskSession) -> some View {
        @Bindable var session = session
        return Form {
            Section {
                LabeledContent("Clínica", value: app.clinicName)
                if !command.isEmpty { Text(command).font(.footnote).foregroundStyle(.secondary) }
                Text("Gravação → transcrição → revisão. Nenhuma receita, diagnóstico ou evolução é salva automaticamente.")
            }
            if session.phase == .ready {
                Section {
                    Toggle("O paciente autorizou a gravação e a transcrição desta consulta", isOn: $session.patientConsent)
                    Toggle("Autorizo o envio deste áudio ao Gemini pelo AtendeBem para transcrição", isOn: $session.aiConsent)
                    Text("A gravação pode conter dados de saúde e vozes de outras pessoas. Grave somente após informar os participantes. O áudio temporário fica protegido neste aparelho e é removido ao enviar ou descartar; o processamento usa o provedor Gemini.").font(.footnote)
                    Button { Task { await session.start() } } label: { Label("Iniciar gravação", systemImage: "mic.fill") }
                        .disabled(!session.canStart).accessibilityIdentifier("lari.audio.start")
                } header: { Text("Antes de gravar") } footer: { Text("Limite de 15 minutos por trecho. Não há gravação em segundo plano.") }
            }
            if session.phase == .requestingPermission { ProgressView(session.preparationMessage) }
            if session.phase == .recording {
                Section {
                    Label("Gravando · \(session.seconds / 60):\(String(format: "%02d", session.seconds % 60))", systemImage: "record.circle")
                        .foregroundStyle(.red)
                    Button("Parar gravação") { session.stopRecording() }.accessibilityIdentifier("lari.audio.stop")
                }
            }
            if session.phase == .audioReady {
                Section {
                    Text("Áudio pronto: \(session.seconds / 60) min \(session.seconds % 60) s. Confira se a gravação corresponde à consulta antes de enviar.")
                    Button("Enviar áudio para transcrever") { session.transcribe() }.accessibilityIdentifier("lari.audio.transcribe")
                    Button("Descartar gravação", role: .destructive) { confirmDiscard = true }
                }
            }
            if session.phase == .transcribing { ProgressView("Transcrevendo o áudio… Isso pode levar até dois minutos.") }
            if let error = session.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    #if os(iOS)
                    if session.needsMicrophoneSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Abrir Ajustes do microfone") { openURL(url) }
                            .accessibilityIdentifier("lari.audio.microphoneSettings")
                    }
                    #endif
                } header: { Text("Confira antes de continuar") }
            }
            if let cleanupError = session.cleanupError {
                Section {
                    Text(cleanupError).foregroundStyle(.red)
                    Button("Tentar excluir áudio") { session.retryCleanup() }.disabled(session.isWorking)
                }
            }
            if session.phase == .expired { Text("Esta tarefa foi encerrada. Abra outra tarefa na clínica atual.") }
            if session.phase == .review {
                Section {
                    TextEditor(text: $session.transcript).frame(minHeight: 240).disabled(applied)
                        .accessibilityLabel("Transcrição para revisão").accessibilityIdentifier("lari.audio.transcript")
                    Text(session.disclaimer).font(.footnote).foregroundStyle(.secondary)
                    Text("Revise nomes, números, doses e negações ouvindo ou conferindo o que foi dito. A identificação automática de falantes não é uma identidade comprovada.").font(.footnote)
                } header: { Text("Revise a transcrição") }
                if let workflow, let baseline {
                    Section {
                        Picker("Acrescentar à seção", selection: $sectionID) {
                            Text("Escolha a seção").tag("")
                            ForEach(baseline.displayedSections) { section in Text(baseline.title(for: section)).tag(section.id) }
                        }.disabled(applied)
                        Toggle("Revisei o texto e a seção de destino", isOn: $reviewed).disabled(applied)
                        if let applicationError { Text(applicationError).foregroundStyle(.red) }
                        if applied { Label("Acrescentado ao rascunho local. Volte à consulta para salvar.", systemImage: "checkmark.circle") }
                        else {
                            if session.transcript.utf16.count > 20_000 { Text("O texto excede 20.000 caracteres. Revise e organize um trecho menor antes de acrescentar.").font(.footnote) }
                            Button("Acrescentar ao rascunho da consulta") { apply(session, workflow: workflow, baseline: baseline) }
                                .disabled(!reviewed || sectionID.isEmpty || session.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.transcript.utf16.count > 20_000)
                        }
                    } footer: { Text("O texto existente será preservado. Esta ação não salva, assina nem encerra a consulta.") }
                }
                Section {
                    ShareLink(item: session.transcript) { Label("Compartilhar transcrição", systemImage: "square.and.arrow.up") }
                    Button("Descartar e gravar outro trecho", role: .destructive) { confirmDiscard = true }
                }
            }
        }
        .onChange(of: session.transcript) { _, _ in reviewed = false }
        .onChange(of: sectionID) { _, _ in reviewed = false }
    }
    private func apply(_ session: LARIAudioTaskSession, workflow: ConsultationWorkflow, baseline: ConsultationContent) {
        guard allowed, session.isContextCurrent, app.user?.canWriteClinicalDraft == true, workflow.canEdit, workflow.phase == .ready,
              workflow.comparison == nil, session.phase == .review, reviewed, !applied else { return }
        do {
            workflow.content = try ConsultationTranscriptMerge.append(session.transcript, sectionID: sectionID, baseline: baseline, current: workflow.content)
            applied = true; applicationError = nil
        } catch { applicationError = error.localizedDescription }
    }
}
