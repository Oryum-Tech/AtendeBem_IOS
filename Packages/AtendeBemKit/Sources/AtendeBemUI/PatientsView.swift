import AtendeBemCore
import SwiftUI

struct PatientsView: View {
    var action: ClinicalShortcut? = nil
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var showCreate = false
    @State private var page = 1
    @State private var resource = RemoteResource<PatientPage>()
    @State private var filters = PatientDirectoryFilters()
    @State private var showFilters = false
    private struct QueryKey: Equatable {
        let search: String
        let page: Int
        let filters: PatientDirectoryFilters
        let context: UUID
        let active: Bool
    }
    private var queryKey: QueryKey { .init(search: search, page: page, filters: filters, context: app.contextID, active: scenePhase == .active) }

    var body: some View {
        Group {
            if app.user?.canReadPatients == true {
                List {
                    if filters.activeCount > 0 {
                        Section("Filtros aplicados") {
                            ForEach(filters.summary, id: \.self) { Text($0).font(.subheadline) }
                            Button("Limpar filtros") { applyFilters(.init()) }
                        }
                    }
                    Section {
                        ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                        if resource.error != nil { Button("Tentar novamente") { Task { await refresh() } } }
                    }
                    if let result = resource.value {
                        if let action {
                            Section { Text("Escolha o paciente para \(action.patientPrompt).").foregroundStyle(.secondary) }
                        }
                        Section("\(result.total) pacientes") {
                            if result.itens.isEmpty {
                                ContentUnavailableView("Nenhum paciente retornado", systemImage: "person.crop.circle.badge.magnifyingglass", description: Text(filters.activeCount > 0 ? "Ajuste os filtros ou tente outra busca." : "Tente outro nome ou CPF."))
                            }
                            ForEach(result.itens) { patient in
                                NavigationLink {
                                    if let action { ClinicalShortcutDestination(action: action, patientID: patient.id) }
                                    else { PatientDetailView(id: patient.id) }
                                }
                                label: { PatientNameRow(patient: patient) }
                            }
                        }
                        if result.total > 25 {
                            Section {
                                HStack {
                                    Button("Anterior") { page -= 1 }.disabled(page == 1)
                                    Spacer()
                                    Text("Página \(page) de \(max(1, (result.total + 24) / 25))").font(.subheadline)
                                    Spacer()
                                    Button("Próxima") { page += 1 }.disabled(page * 25 >= result.total)
                                }.buttonStyle(.bordered).controlSize(.large)
                            }
                        }
                        if result.truncado == true {
                            Label("O serviço retornou parte dos resultados clínicos. Refine a busca; esta lista não representa todos os pacientes que podem corresponder.", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                        }
                        if let missingBirth = result.semNascimento, missingBirth > 0, filters.minimumAge != nil || filters.maximumAge != nil {
                            Label("\(missingBirth) cadastros sem nascimento informado não entram na faixa etária.", systemImage: "person.crop.circle.badge.questionmark").foregroundStyle(.secondary)
                        }
                    }
                }
                .searchable(text: $search, prompt: "Nome ou CPF")
                .onChange(of: search) { _, _ in page = 1; resource.clear() }
                .onChange(of: page) { _, _ in resource.clear() }
                .refreshable { await refresh() }
                .task(id: queryKey) {
                    guard scenePhase == .active else { return }
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                    await refresh(reset: true)
                    // Clinical filters may query several services and generate an audit record.
                    // Re-run them only on an explicit search, refresh or foreground transition.
                    guard filters.activeCount == 0 else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        await refresh()
                    }
                }
            } else { RestrictedState() }
        }.navigationTitle(action?.title ?? "Pacientes")
            .toolbar {
                if app.user?.canReadPatients == true {
                    Button { showFilters = true } label: {
                        Label(filters.activeCount == 0 ? "Filtrar pacientes" : "Filtros (\(filters.activeCount))", systemImage: filters.activeCount == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }.accessibilityIdentifier("patients.filters")
                }
                if app.user?.canCreatePatient == true {
                    Button { showCreate = true } label: { Label("Novo paciente", systemImage: "person.badge.plus") }
                        .accessibilityIdentifier("patients.create")
                }
            }
            .sheet(isPresented: $showCreate) {
                NavigationStack { PatientForm { Task { await refresh() } } }
            }
            .sheet(isPresented: $showFilters) {
                NavigationStack { PatientFiltersView(filters: filters, onApply: applyFilters) }
            }
    }

    private func applyFilters(_ value: PatientDirectoryFilters) {
        filters = value; page = 1; resource.clear()
    }
    private func refresh(reset: Bool = false) async {
        guard let user = app.user else { return }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedPage = page
        let requestedFilters = filters
        await resource.load(reset: reset, app: app) {
            try await PatientDirectoryService(api: app.api).patients(search: query, page: requestedPage, filters: requestedFilters, user: user)
        }
    }
}

struct PatientDetailView: View {
    let id: String
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var resource = RemoteResource<Patient>()
    @State private var history = RemoteResource<VisitSummary>()
    @State private var showEdit = false
    @State private var showAllergy = false

    var body: some View {
        List {
            Section {
                ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                if resource.error != nil { Button("Tentar novamente") { Task { await refresh() } } }
            }
            if let patient = resource.value {
                Section {
                    Text(patient.nome).font(.title2.bold()).textSelection(.enabled)
                    if let cpf = patient.cpfMascarado { LabeledContent("CPF", value: cpf) }
                    if let birth = patient.nascimento { LabeledContent("Nascimento", value: formattedBirth(birth)) }
                    if patient.rascunho == true { Label("Cadastro em aberto", systemImage: "pencil.circle") }
                }
                if app.user?.canReadClinicalData == true {
                    Section {
                        NavigationLink {
                            PatientClinicalChartView(patient: patient)
                        } label: {
                            Label("Problemas, medicações e sinais vitais", systemImage: "heart.text.clipboard")
                        }.accessibilityIdentifier("patient.clinicalChart")
                        NavigationLink {
                            ClinicalActionsView(patient: patient, appointment: nil)
                        } label: {
                            Label("Iniciar atendimento", systemImage: "stethoscope")
                            .fontWeight(.semibold)
                        }
                        NavigationLink {
                            MedicalRecordView(patient: patient)
                        } label: {
                            Label("Evoluções do prontuário", systemImage: "doc.text.magnifyingglass")
                        }
                        NavigationLink {
                            PatientDocumentsView(patient: patient)
                        } label: {
                            Label("Receitas, exames e documentos", systemImage: "doc.on.doc")
                        }.accessibilityIdentifier("patient.documents")
                        NavigationLink {
                            LARIAssistantView(patient: patient)
                        } label: {
                            Label("Organizar anotações com a LARI", systemImage: "sparkles")
                        }
                        LariSummaryButton(patient: patient)
                    } footer: {
                        Text("Atendimento, documentos e histórico clínico no contexto correto deste paciente.")
                    }
                }
                if app.user.map(ExternalExamPolicy.canReceive) == true && app.user?.canReadClinicalData != true {
                    Section {
                        NavigationLink { PatientExamsView(patient: patient) } label: {
                            Label("Exames e resultados", systemImage: "cross.vial")
                        }.accessibilityIdentifier("patient.examResults")
                    } footer: { Text("Recebimento e anexação de exames conforme seu perfil nesta clínica.") }
                }
                Section("Contato") {
                    if let phone = patient.telefone { LabeledContent("Celular", value: phone).textSelection(.enabled) }
                    if let email = patient.email { LabeledContent("E-mail", value: email).textSelection(.enabled) }
                    if patient.telefone == nil && patient.email == nil { Text("Contato não disponível").foregroundStyle(.secondary) }
                }
                if app.user?.canReadClinicalData == true {
                    Section("Alergias e intolerâncias") {
                        if app.user?.canRecordAllergy == true {
                            Button("Registrar alergia ou intolerância") { showAllergy = true }
                        }
                        if let allergies = patient.alergias {
                            if allergies.isEmpty {
                                Text("Nenhuma alergia registrada nesta ficha.").foregroundStyle(.secondary)
                            }
                            ForEach(Array(allergies.enumerated()), id: \.offset) { _, allergy in
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(allergy.substancia, systemImage: allergy.anafilaxia == true ? "exclamationmark.triangle" : "cross.case")
                                        .font(.headline)
                                    Text(allergy.tipo == "intolerancia" ? "Intolerância" : "Alergia")
                                    Text("Severidade: \(allergy.severidade)")
                                    if allergy.anafilaxia == true { Text("Histórico de anafilaxia").bold().foregroundStyle(.red) }
                                    Text(allergy.reacao ?? "Reação não informada").foregroundStyle(.secondary)
                                    if let source = allergy.fonte { Text("Fonte: \(source)").font(.caption).foregroundStyle(.secondary) }
                                    ClinicalTimestamp(label: "Registrada em", value: allergy.criadoEm)
                                }.padding(.vertical, 6)
                            }
                        } else {
                            Text("Informação não disponível para esta consulta.").foregroundStyle(.secondary)
                        }
                    }
                    if let conditions = patient.condicoes, !conditions.isEmpty {
                        Section("Condições registradas") {
                            ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in Text(condition) }
                        }
                    }
                }
                PatientAdditionalDetails(patient: patient)
                Section("Atendimentos na clínica") {
                    if let summary = history.value {
                        LabeledContent("Consultas realizadas", value: String(summary.totalRealizadas))
                        if let last = summary.ultima {
                            Text("Última consulta há \(last.diasAtras) dias.").foregroundStyle(.secondary)
                        }
                    }
                    ConnectionState(updatedAt: history.updatedAt, error: history.error, isLoading: history.isLoading)
                    if history.error != nil { Button("Atualizar histórico") { Task { await refreshHistory() } } }
                }
            }
        }.navigationTitle("Paciente")
            .toolbar {
                if app.user?.canEditPatient == true && resource.value != nil {
                    Button("Editar cadastro") { showEdit = true }
                }
            }
            .sheet(isPresented: $showEdit) {
                if let patient = resource.value {
                    NavigationStack { PatientForm(patient: patient) { Task { await refresh() } } }
                }
            }
            .sheet(isPresented: $showAllergy) {
                NavigationStack { AllergyForm(patientID: id) { Task { await refresh() } } }
            }.inlineTitle()
            .refreshable { await refresh() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await refresh()
                }
            }
    }

    private func refresh() async {
        await resource.load(app: app) {
            let value: Patient = try await app.api.get(["pacientes", id])
            guard value.id == id else { throw APIError.invalidResponse }
            return value
        }
        if resource.value != nil && !Task.isCancelled { await refreshHistory() }
    }

    private func refreshHistory() async {
        await history.load(app: app) { try await app.api.get(["agenda", "pacientes", id, "historico"]) }
    }

    private func formattedBirth(_ value: String) -> String {
        let pieces = value.prefix(10).split(separator: "-")
        guard pieces.count == 3 else { return value }
        return "\(pieces[2])/\(pieces[1])/\(pieces[0])"
    }
}
