import AtendeBemCore
import SwiftUI

struct WriteStatus: View {
    let outcome: WriteOutcome
    let error: String?
    var body: some View {
        if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("write.error") }
        if outcome == .sending { ProgressView("Salvando…") }
        if outcome == .uncertain {
            Label("Não foi possível confirmar o resultado. Atualize a lista e confira se o registro foi salvo antes de criar outro.", systemImage: "exclamationmark.triangle")
        }
    }
}

extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct PatientPickerView: View {
    let select: (Patient) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var resource = RemoteResource<PatientPage>()
    var body: some View {
        List {
            if let result = resource.value {
                if result.itens.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(result.itens) { patient in
                    Button { select(patient); dismiss() } label: { PatientNameRow(patient: patient) }
                }
                if result.total > result.itens.count { Text("Refine a busca para encontrar o paciente.").foregroundStyle(.secondary) }
            }
            ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
            if resource.error != nil { Button("Tentar novamente") { Task { await load() } } }
        }
        .navigationTitle("Escolher paciente")
        .searchable(text: $search, prompt: "Nome ou CPF")
        .task(id: search) {
            resource.clear()
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await load()
        }
    }
    private func load() async {
        let query = search
        await resource.load(app: app) { try await ClinicalService(api: app.api).patients(search: query, page: 1) }
    }
}

struct AppointmentForm: View {
    var appointment: Appointment? = nil
    var initialDate: Date = .now
    let saved: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var initialized = false
    @State private var duration = 30
    @State private var patient: Patient?
    @State private var professionalID = ""
    @State private var typeID = ""
    @State private var channel = "presencial"
    @State private var catalog = RemoteResource<AppointmentTypeCatalog>()
    @State private var team = RemoteResource<[User]>()
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?

    private var valid: Bool {
        outcome.canSubmit && (appointment != nil || (patient != nil && !professionalID.isEmpty && !typeID.isEmpty))
    }
    var body: some View {
        Form {
            if appointment == nil {
                Section("Paciente e profissional") {
                    NavigationLink { PatientPickerView { patient = $0 } } label: {
                        LabeledContent("Paciente", value: patient?.nome ?? "Selecionar")
                    }
                    Picker("Profissional", selection: $professionalID) {
                        Text("Selecionar").tag("")
                        ForEach((team.value ?? []).filter { !Set($0.papeis).isDisjoint(with: User.careRoles) }) { user in
                            Text(user.nome).tag(user.id)
                        }
                    }
                    if let error = team.error { Text(error).foregroundStyle(.red) }
                    Picker("Tipo", selection: $typeID) {
                        Text("Selecionar").tag("")
                        ForEach((catalog.value?.itens ?? []).filter(\.ativo)) { type in Text(type.rotulo).tag(type.id) }
                    }
                    if let error = catalog.error { Text(error).foregroundStyle(.red) }
                    if team.error != nil || catalog.error != nil { Button("Recarregar opções") { Task { await loadOptions() } } }
                    Picker("Canal", selection: $channel) {
                        Text("Presencial").tag("presencial")
                        Text("Teleconsulta").tag("teleconsulta")
                    }
                }.disabled(outcome != .ready)
            }
            Section {
                DatePicker("Horário", selection: $date)
                    .environment(\.timeZone, ClinicClock.timeZone)
                Stepper("Duração: \(duration) minutos", value: $duration, in: 5...480, step: 5)
            } footer: { Text("Horário da clínica: UTC−03:00. A disponibilidade é conferida pelo servidor ao salvar.") }
                .disabled(outcome != .ready)
            Section {
                WriteStatus(outcome: outcome, error: error)
                Button(appointment == nil ? "Criar agendamento" : "Salvar novo horário") { Task { await submit() } }
                    .disabled(!valid).accessibilityIdentifier("appointment.save")
            }
        }
        .navigationTitle(appointment == nil ? "Novo agendamento" : "Reagendar")
        .inlineTitle()
        .interactiveDismissDisabled(outcome == .sending)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.disabled(outcome == .sending) } }
        .task {
            guard !initialized else { return }
            initialized = true
            date = appointment?.startDate ?? initialDate
            duration = appointment?.duracaoMin ?? 30
            if appointment == nil { await loadOptions() }
        }
    }
    private func loadOptions() async {
        await team.load(app: app) { try await app.api.get(["usuarios"]) }
        await catalog.load(app: app) { try await app.api.get(["agenda", "tipos-atendimento"]) }
        if professionalID.isEmpty, let user = app.user, user.canReadClinicalData,
           team.value?.contains(where: { $0.id == user.id }) == true { professionalID = user.id }
    }
    private func submit() async {
        guard valid, let user = app.user, user.canConfirmAppointment else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            if let appointment {
                _ = try await AppointmentService(api: app.api).reschedule(appointment, date: date, duration: duration, user: user)
            } else if let patient {
                let _: Appointment = try await app.api.post(["agendamentos"], body: AppointmentInput(date: date, duration: duration,
                    patientID: patient.id, professionalID: professionalID, type: typeID, channel: channel))
            }
            guard app.contextID == context else { return }
            outcome = .succeeded; saved(); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

struct PatientForm: View {
    var patient: Patient? = nil
    let saved: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var initialized = false
    @State private var cpf = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var birth = Date.now
    @State private var includeBirth = false
    @State private var nursingTerm = false
    @State private var duplicateReview = false
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var matches = RemoteResource<PatientPage>()

    private var valid: Bool {
        guard name.trimmedOrNil != nil, outcome.canSubmit else { return false }
        if !email.isEmpty && (!email.contains("@") || email.contains(" ")) { return false }
        if patient == nil && (!duplicateReview || matches.value == nil || matches.error != nil || matches.isLoading) { return false }
        if patient == nil && app.user?.needsNursingRegistrationTerm == true && !nursingTerm { return false }
        // The current PATCH contract cannot clear these fields with an empty string.
        if patient?.telefone != nil && phone.trimmedOrNil == nil { return false }
        if patient?.email != nil && email.trimmedOrNil == nil { return false }
        return true
    }
    var body: some View {
        Form {
            Section("Identificação") {
                TextField("Nome completo", text: $name).accessibilityIdentifier("patient.name")
                if patient == nil { TextField("CPF (opcional)", text: $cpf).textContentType(.none) }
                Toggle("Informar nascimento", isOn: $includeBirth).disabled(patient?.nascimento != nil)
                if includeBirth { DatePicker("Nascimento", selection: $birth, in: ...Date.now, displayedComponents: .date).environment(\.timeZone, ClinicClock.timeZone) }
            }.disabled(outcome != .ready)
            Section {
                TextField("Celular", text: $phone).textContentType(.telephoneNumber)
                TextField("E-mail", text: $email).emailInput().textContentType(.emailAddress)
            } header: { Text("Contato") } footer: {
                if patient != nil { Text("Os demais dados do cadastro são preservados. Para corrigir um contato existente, informe o novo valor.") }
            }.disabled(outcome != .ready)
            if patient == nil, name.trimmedOrNil != nil {
                Section {
                    if matches.isLoading { ProgressView("Conferindo cadastros…") }
                    if let error = matches.error { Text(error).foregroundStyle(.red); Button("Conferir novamente") { Task { await findMatches() } } }
                    ForEach(matches.value?.itens ?? []) { match in
                        NavigationLink { PatientDetailView(id: match.id) } label: { PatientNameRow(patient: match) }
                    }
                    Toggle("Conferi os resultados e preciso criar um novo cadastro", isOn: $duplicateReview)
                } header: { Text("Evitar cadastro duplicado") } footer: {
                    Text("A busca por nome é uma ajuda, não uma confirmação de identidade. Confira nome, nascimento e CPF antes de continuar.")
                }.disabled(outcome != .ready)
                if app.user?.needsNursingRegistrationTerm == true {
                    Section {
                        Toggle("Declaro, como profissional de enfermagem, responsabilidade pela veracidade do cadastro. O aceite fica registrado na auditoria.", isOn: $nursingTerm)
                    }
                }
            }
            Section {
                WriteStatus(outcome: outcome, error: error)
                Button(patient == nil ? "Cadastrar paciente" : "Salvar alterações") { Task { await submit() } }
                    .disabled(!valid).accessibilityIdentifier("patient.save")
            }
        }
        .navigationTitle(patient == nil ? "Novo paciente" : "Editar cadastro").inlineTitle()
        .interactiveDismissDisabled(outcome == .sending)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.disabled(outcome == .sending) } }
        .task {
            guard !initialized else { return }
            initialized = true
            guard let patient else { return }
            name = patient.nome; phone = patient.telefone ?? ""; email = patient.email ?? ""
            if let value = patient.nascimento, let parsed = ClinicClock.parseInstant(value + "T12:00:00-03:00") { birth = parsed; includeBirth = true }
        }
        .task(id: name) {
            guard patient == nil else { return }
            matches.clear(); duplicateReview = false
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            if name.trimmedOrNil != nil { await findMatches() }
        }
    }
    private func findMatches() async {
        let query = name
        await matches.load(app: app) { try await ClinicalService(api: app.api).patients(search: query, page: 1) }
    }
    private func submit() async {
        guard valid, let user = app.user, patient == nil ? user.canCreatePatient : user.canEditPatient else { return }
        outcome = .sending; error = nil
        let input = PatientInput(name: name.trimmedOrNil ?? name, cpf: patient == nil ? cpf.trimmedOrNil : nil,
            birth: includeBirth ? ClinicClock.day(birth) : nil, phone: phone.trimmedOrNil, email: email.trimmedOrNil,
            nursingTerm: patient == nil && user.needsNursingRegistrationTerm ? nursingTerm : nil)
        do {
            if let patient { let _: Patient = try await app.api.patch(["pacientes", patient.id], body: input) }
            else { let _: Patient = try await app.api.post(["pacientes"], body: input) }
            outcome = .succeeded; saved(); dismiss()
        } catch {
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

struct AllergyForm: View {
    let patientID: String
    let saved: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var substance = ""
    @State private var type = "alergia"
    @State private var severity = "leve"
    @State private var anaphylaxis = false
    @State private var reaction = ""
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    var body: some View {
        Form {
            Section("Relato do paciente") {
                TextField("Substância", text: $substance)
                Picker("Tipo", selection: $type) { Text("Alergia").tag("alergia"); Text("Intolerância").tag("intolerancia") }
                Picker("Severidade", selection: $severity) { Text("Leve").tag("leve"); Text("Moderada").tag("moderada"); Text("Grave").tag("grave") }
                Toggle("Histórico de anafilaxia", isOn: $anaphylaxis)
                TextField("Reação relatada (opcional)", text: $reaction, axis: .vertical)
            }.disabled(outcome != .ready)
            Section {
                WriteStatus(outcome: outcome, error: error)
                Button("Registrar alergia ou intolerância") { Task { await submit() } }
                    .disabled(!outcome.canSubmit || substance.trimmedOrNil == nil || reaction.count > 400)
            } footer: { Text("Registre o que foi relatado ou confirmado. Reação não informada permanece sem descrição.") }
        }.navigationTitle("Alergia ou intolerância").inlineTitle()
            .interactiveDismissDisabled(outcome == .sending)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.disabled(outcome == .sending) } }
    }
    private func submit() async {
        guard outcome.canSubmit, let substance = substance.trimmedOrNil, app.user?.canRecordAllergy == true else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: Allergy = try await app.api.post(["pacientes", patientID, "alergias"], body: AllergyInput(substance: substance,
                type: type, severity: severity, anaphylaxis: anaphylaxis, reaction: reaction.trimmedOrNil))
            guard app.contextID == context else { return }
            outcome = .succeeded; saved(); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}
