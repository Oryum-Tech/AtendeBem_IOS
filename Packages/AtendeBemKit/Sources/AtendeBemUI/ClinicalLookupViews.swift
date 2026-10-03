import AtendeBemCore
import SwiftUI

struct MedicineLookup: View {
    @Binding var medicine: String
    @Environment(AppState.self) private var app
    @State private var result = RemoteResource<MedicineSearch>()
    @State private var selectedName: String?
    private var query: String { medicine.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Medicamento", text: $medicine)
            if query.count >= 2 && selectedName != medicine {
                if result.isLoading { ProgressView("Buscando no catálogo…") }
                if let error = result.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                ForEach(result.value?.itens ?? []) { item in
                    Button {
                        selectedName = item.nomeProduto; medicine = item.nomeProduto; result.clear()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.nomeProduto).font(.subheadline.bold())
                            if let active = item.principioAtivo { Text(active).font(.caption) }
                            if let company = item.empresa { Text(company).font(.caption).foregroundStyle(.secondary) }
                            Text("Situação: \(item.situacao)").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.borderless)
                }
                if result.value?.itens.isEmpty == true { Text("Nenhum resultado. Confira a grafia ou informe o medicamento manualmente.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: medicine) { _, _ in result.clear() }
        .task(id: query) {
            guard query.count >= 2, selectedName != medicine else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            let requested = query
            await result.load(reset: true, app: app) {
                try await app.api.get(["medicamentos"], query: [.init(name: "busca", value: requested), .init(name: "perPage", value: "8")])
            }
        }
    }
}

struct ClinicalCodePicker: View {
    let onSelect: (ClinicalCode) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var result = RemoteResource<[ClinicalCode]>()
    var body: some View {
        List {
            ConnectionState(updatedAt: result.updatedAt, error: result.error, isLoading: result.isLoading)
            if search.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Text("Busque pelo código ou pela descrição do CID-10.").foregroundStyle(.secondary)
            }
            ForEach(result.value ?? []) { item in
                Button { onSelect(item); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.codigo).font(.headline)
                        Text(item.descricao).foregroundStyle(.primary)
                    }.frame(minHeight: 44)
                }
            }
            if result.value?.isEmpty == true { ContentUnavailableView.search(text: search) }
        }
        .navigationTitle("Buscar CID-10").inlineTitle()
        .searchable(text: $search, prompt: "Código ou descrição")
        .toolbar { Button("Fechar") { dismiss() } }
        .onChange(of: search) { _, _ in result.clear() }
        .task(id: search) {
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2 else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await result.load(reset: true, app: app) { try await app.api.get(["sugestoes", "cid"], query: [.init(name: "q", value: query)]) }
        }
    }
}

struct PatientHistorySection: View {
    let patientID: String
    @Environment(AppState.self) private var app
    @State private var history = RemoteResource<PatientHistory>()
    @State private var expanded = false
    var body: some View {
        Section("História médica pregressa") {
            if let value = history.value {
                Text(value.social?.trimmedOrNil ?? "História social não informada").lineLimit(expanded ? nil : 2)
                DisclosureGroup(expanded ? "Menos dados" : "Mais dados", isExpanded: $expanded) {
                    field("Familiar", value.familiar)
                    field("Ocupacional", value.ocupacional)
                    field("Esportiva", value.esportiva)
                    LabeledContent("Quedas nos últimos 12 meses", value: value.fallsLabel)
                    field("Detalhes das quedas", value.quedasDetalhe)
                    field("Cirurgias na região", value.cirurgiasRegiao)
                    field("Fisioterapia prévia", value.fisioterapiaPrevia)
                    field("Dominância", value.dominancia)
                    if let raw = value.atualizadoEm, let date = ClinicClock.parseInstant(raw) {
                        Text("Registro atualizado em \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ConnectionState(updatedAt: history.updatedAt, error: history.error, isLoading: history.isLoading)
            if history.error != nil { Button("Tentar novamente") { Task { await load() } } }
        }.task(id: patientID) { await load() }
    }
    private func field(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text?.trimmedOrNil ?? "Não informado").textSelection(.enabled)
        }.padding(.vertical, 3)
    }
    private func load() async {
        guard app.user?.canReadClinicalData == true else { return }
        await history.load(app: app) { try await app.api.get(["pacientes", patientID, "antecedentes"]) }
    }
}
