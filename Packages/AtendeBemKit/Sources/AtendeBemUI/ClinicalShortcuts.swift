import AtendeBemCore
import SwiftUI

enum ClinicalShortcut: String, CaseIterable, Codable, Identifiable {
    case prescription, exams, consultation, lari
    var id: String { rawValue }
    var title: String {
        switch self { case .prescription: "Receitas"; case .exams: "Exames"; case .consultation: "Consulta"; case .lari: "LARI" }
    }
    var symbol: String {
        switch self { case .prescription: "pills"; case .exams: "cross.vial"; case .consultation: "stethoscope"; case .lari: "sparkles" }
    }
    var patientPrompt: String {
        switch self { case .prescription: "criar uma receita"; case .exams: "solicitar exames"; case .consultation: "abrir a consulta"; case .lari: "conversar com a LARI" }
    }
    func isAllowed(for user: User?) -> Bool {
        switch self {
        case .prescription: user?.canPrescribe == true
        case .exams: user?.canRequestExam == true
        case .consultation: user?.canWriteClinicalDraft == true
        case .lari: user?.canUseLARI == true
        }
    }
}

struct ClinicalShortcutDestination: View {
    let action: ClinicalShortcut
    let patientID: String
    @Environment(AppState.self) private var app
    @State private var patient = RemoteResource<Patient>()

    var body: some View {
        Group {
            if !action.isAllowed(for: app.user) { RestrictedState() }
            else if let value = patient.value {
                switch action {
                case .prescription: PrescriptionForm(patient: value)
                case .exams: ExamRequestForm(patient: value)
                case .consultation: ConsultationView(patient: value, appointment: nil)
                case .lari: LARIChatView()
                }
            } else if let error = patient.error {
                RetryState(title: "Não foi possível abrir o paciente", detail: error) { Task { await load() } }
            } else { ProgressView("Abrindo paciente…") }
        }.task { await load() }
    }
    private func load() async {
        guard action.isAllowed(for: app.user) else { return }
        await patient.load(app: app) { try await app.api.get(["pacientes", patientID]) }
    }
}
