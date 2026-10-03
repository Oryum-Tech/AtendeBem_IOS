import AtendeBemCore
import SwiftUI

struct PatientFiltersView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PatientDirectoryFilters
    @State private var minimumAge: String
    @State private var maximumAge: String
    let onApply: (PatientDirectoryFilters) -> Void

    init(filters: PatientDirectoryFilters, onApply: @escaping (PatientDirectoryFilters) -> Void) {
        _draft = State(initialValue: filters)
        _minimumAge = State(initialValue: filters.minimumAge.map(String.init) ?? "")
        _maximumAge = State(initialValue: filters.maximumAge.map(String.init) ?? "")
        self.onApply = onApply
    }
    private var validated: Result<PatientDirectoryFilters, Error> {
        Result {
            var value = draft
            value.minimumAge = try PatientDirectoryFilters.parseAge(minimumAge)
            value.maximumAge = try PatientDirectoryFilters.parseAge(maximumAge)
            guard let user = app.user else { throw APIError.sessionExpired }
            _ = try value.queryItems(search: "", page: 1, user: user)
            return value
        }
    }
    private var validationError: String? {
        if case .failure(let error) = validated { return error.localizedDescription }
        return nil
    }
    var body: some View {
        Form {
            Section {
                Picker("Pacientes", selection: $draft.segment) {
                    ForEach(PatientSegment.allCases.filter { !$0.requiresClinicalAccess || app.user?.canUseClinicalPatientFilters == true }) {
                        Text($0.title).tag($0)
                    }
                }
                Toggle("Incluir cadastros arquivados", isOn: Binding(get: { draft.includesArchived }, set: { draft.includeArchived = $0 }))
                    .disabled(draft.segment == .inactive)
            } header: {
                Text("Acompanhamento")
            } footer: {
                Text(draft.segment == .inactive ? "Este acompanhamento inclui cadastros arquivados automaticamente, conforme a regra da clínica. Nenhum cadastro será alterado." : "Os filtros consultam os pacientes da clínica ativa. Nenhum cadastro será alterado.")
            }
            Section {
                TextField("Idade mínima", text: $minimumAge).ageKeyboard().accessibilityIdentifier("patients.minimumAge")
                TextField("Idade máxima", text: $maximumAge).ageKeyboard().accessibilityIdentifier("patients.maximumAge")
            } header: { Text("Faixa etária")
            } footer: { Text("Os limites são inclusivos. Pacientes sem nascimento informado não entram na faixa etária.") }
            if app.user?.canUseClinicalPatientFilters == true {
                Section {
                    TextField("Condição, doença ou CID", text: $draft.condition)
                    TextField("Medicamento", text: $draft.medication)
                } header: { Text("Informações clínicas")
                } footer: { Text("Refine a busca com os registros disponíveis. Estes filtros não substituem a revisão do prontuário.") }
            }
            if let validationError { Section { Label(validationError, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
            Section {
                Button("Limpar filtros") { draft = .init(); minimumAge = ""; maximumAge = "" }
                    .disabled(draft.activeCount == 0 && minimumAge.isEmpty && maximumAge.isEmpty)
            }
        }
        .navigationTitle("Filtrar pacientes").inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Aplicar") {
                    if case .success(let value) = validated { onApply(value); dismiss() }
                }.disabled(validationError != nil).accessibilityIdentifier("patients.applyFilters")
            }
        }
    }
}

private extension View {
    @ViewBuilder func ageKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
