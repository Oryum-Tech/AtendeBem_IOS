import AtendeBemCore
import SwiftUI

/// A fresh presentation each time; opening the button never generates a summary.
struct LariSummaryButton: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var presented = false

    var body: some View {
        if app.user.map(LariSummaryPolicy.canGenerate) == true {
            Button { presented = true } label: {
                Label("Preparar consulta com fontes", systemImage: "text.magnifyingglass")
            }
            .accessibilityIdentifier("lari.summary.open")
            .sheet(isPresented: $presented) {
                NavigationStack { LariSummaryView(patient: patient) }
            }
        }
    }
}

private struct LariSummaryView: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var session: LariSummarySession?
    @State private var task: Task<Void, Never>?
    @State private var confirmGeneration = false
    @State private var confirmClose = false

    var body: some View {
        Group {
            if app.user.map(LariSummaryPolicy.canGenerate) != true { RestrictedState() }
            else if let session { content(session) }
            else { ProgressView("Preparando a tela…") }
        }
        .navigationTitle("Preparar consulta").inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") {
                    if session?.phase == .generating { confirmClose = true }
                    else { close() }
                }
            }
        }
        .interactiveDismissDisabled(session?.phase == .generating || session?.phase == .checkingSession)
        .task {
            // Only constructs local state. There is no summary fetch in the appearance lifecycle.
            guard session == nil, let user = app.user, LariSummaryPolicy.canGenerate(user) else { return }
            let context = app.contextID
            let requestContext = await app.api.requestContextID()
            guard app.contextID == context, !Task.isCancelled else { return }
            session = LariSummarySession(api: app.api, context: requestContext, patientID: patient.id, userID: user.id)
        }
        .onChange(of: app.contextID) { _, _ in close() }
        .onChange(of: app.user?.papeis) { _, _ in close() }
        .onChange(of: patient.id) { _, _ in close() }
        .onDisappear { task?.cancel(); session?.invalidate() }
        .confirmationDialog("Gerar outro resumo?", isPresented: $confirmGeneration, titleVisibility: .visible) {
            Button("Consultar prontuário e gerar novamente") { generate() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Isso inicia outro processamento dos dados estruturados deste paciente e substitui o resumo desta tela. Se a solicitação anterior foi interrompida, ela ainda pode ter sido processada. A evolução não será alterada.")
        }
        .confirmationDialog("Fechar enquanto o resumo é preparado?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Continuar aguardando", role: .cancel) {}
            Button("Parar espera e fechar", role: .destructive) { close() }
        } message: { Text("O serviço ainda pode concluir o processamento. O aplicativo não enviará outra solicitação automaticamente.") }
    }

    private func content(_ session: LariSummarySession) -> some View {
        List {
            Section {
                LabeledContent("Paciente", value: patient.nome)
                LabeledContent("Clínica", value: app.clinicName)
                Label("Apoio à leitura com IA", systemImage: "sparkles").font(.headline)
                Text("Leia uma narrativa com referências, os fatos estruturados e os trechos de origem. Este apoio não é uma evolução, não pode ser assinado e não preenche as anotações da consulta.")
            }
            consentSection(session)
            actionSection(session)
            if let summary = session.summary {
                activitySection(summary)
                narrativeSection(summary)
                ForEach(LariSummaryCategory.allCases, id: \.self) { category in
                    let facts = summary.fatos.filter { $0.categoria == category }
                    if !facts.isEmpty {
                        Section(category.title) {
                            ForEach(facts) { fact in LariSummaryFactRow(fact: fact) }
                        }
                    }
                }
                excerptsSection(summary)
                Section {
                    Text(summary.disclaimer).font(.footnote)
                    Text("Confira cada informação na sua fonte e no atendimento. Uma referência encontrada não comprova que a frase da IA está clinicamente correta.")
                        .font(.footnote)
                } header: { Text("Revisão profissional") }
            }
        }
    }

    private func consentSection(_ session: LariSummarySession) -> some View {
        Section {
            Text("Os fatos estruturados do prontuário deste paciente poderão ser enviados à Anthropic (Claude) ou Google (Gemini), conforme a configuração do serviço, para preparar a narrativa. A IA pode errar ou omitir informações. Confira as condições de privacidade da clínica antes de autorizar.")
                .font(.footnote)
            DisclosureGroup("Como os dados serão usados") {
                Text("Ao gerar, o identificador deste paciente será enviado à LARI para consultar o prontuário nesta clínica. Use apenas informações que você está autorizado a tratar.")
                Text("Os trechos livres das evoluções são apresentados para sua leitura, sem envio ao modelo nem reescrita por IA. O serviço registra a geração na trilha da LARI, sem gravar uma evolução.")
            }.font(.footnote)
            Toggle("Autorizo consultar o prontuário e processar os fatos com IA", isOn: Binding(
                get: { session.agreedToProcessing }, set: { session.agreedToProcessing = $0 }
            )).accessibilityIdentifier("lari.summary.consent")
                .disabled(task != nil || session.phase == .expired || session.phase == .sessionRejected)
        } header: { Text("Antes de gerar") } footer: {
            Text("O resumo fica somente nesta tela. Ao fechá-la, será descartado do aplicativo. Nenhuma geração acontece apenas ao abrir a ficha.")
        }
    }

    private func actionSection(_ session: LariSummarySession) -> some View {
        Section {
            if session.phase == .generating {
                ProgressView("Consultando as fontes e preparando o resumo…")
                Button("Parar espera") { task?.cancel(); session.stopWaiting() }
            } else if session.phase == .checkingSession {
                ProgressView("Conferindo a sessão…")
            } else if session.phase == .sessionRejected {
                Button("Conferir sessão sem gerar resumo") { checkSession() }
                    .disabled(task != nil).accessibilityIdentifier("lari.summary.checkSession")
            } else {
                Button {
                    if session.hasRequested { confirmGeneration = true } else { generate() }
                } label: {
                    Label(session.hasRequested ? "Gerar novo resumo" : "Gerar resumo com fontes", systemImage: "sparkles")
                }.disabled(task != nil || !session.canGenerate)
                    .accessibilityIdentifier("lari.summary.generate")
            }
            if let error = session.failure {
                Text(error is LariSummaryFailure ? error.localizedDescription : message(for: error))
                    .foregroundStyle(error as? LariSummaryFailure == .sessionChecked ? Color.secondary : Color.red)
                    .accessibilityIdentifier("lari.summary.error")
                if error as? LariSummaryFailure != .sessionChecked {
                    Text("Nenhuma solicitação será repetida automaticamente. Você pode fechar esta tela e consultar as evoluções e os dados clínicos diretamente.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func activitySection(_ summary: LariSummaryResponse) -> some View {
        Section {
            ClinicalTimestamp(label: "Geração", value: summary.geradoEm)
            LabeledContent("Evoluções informadas pelo serviço", value: String(summary.atividade.totalEvolucoes))
            LabeledContent("Ainda não assinadas", value: String(summary.atividade.naoAssinadas))
            ClinicalTimestamp(label: "Primeira evolução", value: summary.atividade.primeiraEm)
            ClinicalTimestamp(label: "Última evolução", value: summary.atividade.ultimaEm)
            Text("O extrato retornou \(summary.fatos.count) fatos e \(summary.trechos.count) trechos de \(summary.returnedEvolutionCount) evoluções. É um recorte do prontuário; registros sem texto ou fora dos limites do serviço podem não aparecer aqui.")
                .font(.footnote)
            Text("A narrativa pode usar apenas parte desses fatos. Para histórico completo, consulte as telas de prontuário e dados clínicos.")
                .font(.footnote)
        } header: { Text("Alcance deste extrato") } footer: { Text("Horários apresentados em UTC−03:00. A data de geração não é a data dos registros de origem.") }
    }

    @ViewBuilder private func narrativeSection(_ summary: LariSummaryResponse) -> some View {
        Section {
            if summary.hasMatchedNarrative, let narrative = summary.narrativa {
                ForEach(Array(narrative.frases.enumerated()), id: \.offset) { _, sentence in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(sentence.texto).textSelection(.enabled)
                        if let facts = summary.facts(for: sentence) {
                            DisclosureGroup("Conferir \(facts.count) fatos citados") {
                                ForEach(facts) { fact in LariSummaryFactRow(fact: fact) }
                            }.font(.footnote)
                        }
                    }.padding(.vertical, 4)
                }
            } else if let notice = summary.narrativeNotice { Text(notice) }
        } header: { Label("Narrativa gerada por IA", systemImage: "sparkles") } footer: {
            if summary.hasMatchedNarrative {
                Text("As referências foram correspondidas aos fatos deste extrato. Abra cada grupo para comparar o texto da IA com o conteúdo e a origem retornados; isso não é validação clínica.")
            } else {
                Text("Os dados de origem aparecem a seguir para sua leitura, independentemente da disponibilidade da narrativa.")
            }
        }
    }

    private func excerptsSection(_ summary: LariSummaryResponse) -> some View {
        Section {
            if summary.trechos.isEmpty { Text("Nenhum trecho de evolução foi retornado neste extrato. Isso não comprova ausência de histórico.").foregroundStyle(.secondary) }
            ForEach(summary.trechos) { excerpt in
                DisclosureGroup {
                    Text(excerpt.texto).textSelection(.enabled)
                    LabeledContent("Tipo retornado", value: excerpt.tipo)
                    Text("Nome do profissional não informado neste extrato").font(.caption).foregroundStyle(.secondary)
                    LariSummarySourceRow(source: excerpt.fonte, reference: excerpt.ref, professionalID: excerpt.profissionalId)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(excerpt.secaoTitulo ?? "Seção \(excerpt.secaoId)").font(.headline)
                        LariSummaryDate(value: excerpt.data)
                        Text(excerpt.assinado ? "Registro assinado" : "Registro ainda não assinado")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: { Text("Trechos de origem") } footer: {
            Text("Texto como devolvido pelo serviço, sem reescrita pelo aplicativo ou pelo modelo. A formatação original da evolução pode ter sido convertida em texto simples pelo serviço.")
        }
    }

    private func generate() {
        guard task == nil, let session, let user = app.user, session.canGenerate else { return }
        let context = app.contextID
        task = Task {
            await session.generate(patientID: patient.id, user: user)
            guard app.contextID == context else { return }
            task = nil
            if let error = session.failure { await app.checkSession(after: error) }
        }
    }
    private func checkSession() {
        guard task == nil, let session else { return }
        let context = app.contextID
        task = Task {
            await session.checkSession()
            guard app.contextID == context else { return }
            task = nil
            if let error = session.failure { await app.checkSession(after: error) }
        }
    }
    private func close() { task?.cancel(); session?.invalidate(); dismiss() }
}

private struct LariSummaryFactRow: View {
    let fact: LariSummaryFact
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fact.rotulo).font(.headline).textSelection(.enabled)
            if let detail = fact.detalhe { Text(detail).textSelection(.enabled) }
            LariSummaryDate(value: fact.data)
            LariSummarySourceRow(source: fact.fonte, reference: fact.ref)
        }.padding(.vertical, 4)
    }
}

private struct LariSummarySourceRow: View {
    let source: LariSummarySource
    let reference: String
    var professionalID: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fonte: \(source.title) · referência \(reference)")
            DisclosureGroup("Detalhes da origem") {
                Text("Identificador do registro: \(source.id)")
                if let professionalID, !professionalID.isEmpty { Text("Identificador do profissional: \(professionalID)") }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private struct LariSummaryDate: View {
    let value: String?
    var body: some View {
        if let civilDate {
            Text("Data do registro: \(civilDate)").font(.caption).foregroundStyle(.secondary)
        } else { ClinicalTimestamp(label: "Data do registro", value: value) }
    }
    private var civilDate: String? {
        guard let value, value.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ClinicClock.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}
