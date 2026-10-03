import AtendeBemCore
import Foundation
import Observation
import SwiftUI

/// Session-only working notes. No clinical content is written to local storage.
@MainActor @Observable
final class ConsultationSessionStore {
    struct Key: Hashable {
        let uiContext: UUID
        let apiContext: UUID
        let clinicID: String
        let authorID: String
        let patientID: String
    }

    struct Entry: Identifiable {
        let id: UUID
        let key: Key
        let patientName: String
        let workflow: ConsultationWorkflow

        @MainActor var status: String {
            switch workflow.phase {
            case .uncertainConfirmation: "Confirmação a conferir"
            case .uncertainSave: "Salvamento a conferir"
            case .saving, .confirming, .loading: "Operação em andamento"
            default: workflow.hasUnsavedChanges ? "Anotações não salvas" : "Rascunho para continuar"
            }
        }
    }

    private(set) var entries: [Entry] = []

    var continuations: [Entry] {
        entries.filter {
            let workflow = $0.workflow
            return workflow.loaded && workflow.phase != .expired && workflow.phase != .confirmed
                && (workflow.content.hasContent || workflow.hasUnsavedChanges
                    || [.uncertainSave, .uncertainConfirmation].contains(workflow.phase))
        }
    }

    func session(key: Key, patientName: String, create: () -> ConsultationWorkflow) -> Entry {
        if let existing = entries.first(where: { $0.key == key }) { return existing }
        let entry = Entry(id: UUID(), key: key, patientName: patientName, workflow: create())
        entries.append(entry)
        return entry
    }

    func entry(id: UUID) -> Entry? { entries.first { $0.id == id } }

    /// An uncertain write must remain reconcilable. Discard never deletes a server draft.
    @discardableResult func discard(id: UUID) -> Bool {
        guard let entry = entry(id: id), !entry.workflow.isBusy,
              ![.uncertainSave, .uncertainConfirmation].contains(entry.workflow.phase) else { return false }
        entry.workflow.invalidate()
        entries.removeAll { $0.id == id }
        return true
    }

    func invalidate(id: UUID) {
        entry(id: id)?.workflow.invalidate()
        entries.removeAll { $0.id == id }
    }

    func invalidateAll() {
        for entry in entries { entry.workflow.invalidate() }
        entries.removeAll()
    }
}

/// Refetch only the patient needed by existing consultation/document forms; the store keeps no profile.
struct ContinueConsultationView: View {
    let sessionID: UUID
    @Environment(AppState.self) private var app
    @State private var patient: Patient?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Group {
            if app.user?.canReadClinicalData != true { RestrictedState() }
            else if let entry = app.consultations.entry(id: sessionID), entry.workflow.phase != .expired {
                if let patient { ConsultationView(patient: patient, appointment: nil) }
                else if let error {
                    RetryState(title: "Não foi possível retomar", detail: error) { Task { await load() } }
                } else { ProgressView("Conferindo paciente…") }
            } else {
                ContentUnavailableView("Consulta indisponível nesta sessão", systemImage: "doc.badge.clock",
                    description: Text("A sessão mudou ou estas anotações foram descartadas. Abra a ficha do paciente para consultar o rascunho salvo no servidor."))
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard !loading, patient == nil, app.user?.canReadClinicalData == true,
              let entry = app.consultations.entry(id: sessionID), entry.workflow.phase != .expired else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let value: Patient = try await app.api.get(["pacientes", entry.key.patientID])
            try Task.checkCancellation()
            guard app.contextID == entry.key.uiContext, app.consultations.entry(id: sessionID) != nil,
                  entry.workflow.phase != .expired else { return }
            guard value.id == entry.key.patientID else { throw APIError.invalidResponse }
            patient = value
        } catch is CancellationError {
        } catch {
            guard app.contextID == entry.key.uiContext else { return }
            if let apiError = error as? APIError,
               [.http(401), .http(403), .http(404), .sessionExpired, .contextChanged].contains(apiError) {
                app.consultations.invalidate(id: sessionID)
                patient = nil
            }
            self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}
