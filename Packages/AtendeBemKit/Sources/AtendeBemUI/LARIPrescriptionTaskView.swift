import AtendeBemCore
import SwiftUI

struct LARIPrescriptionTaskView: View {
    let command: String
    var task: LARIPrescriptionTask? = nil
    var onTaskReady: ((LARIPrescriptionTask) -> Void)? = nil
    @Environment(AppState.self) private var app
    @State private var model: LARIPrescriptionTask?
    @State private var openReview = false

    var body: some View {
        Group {
            if let model { content(model) }
            else if app.user?.canPrescribe != true {
                ContentUnavailableView("Prescrição restrita", systemImage: "lock", description: Text("A emissão de receitas está disponível para os perfis médico e dentista autorizados nesta clínica."))
            } else { ProgressView("Preparando sua solicitação…") }
        }
        .navigationTitle("Receita com LARI").inlineTitle()
        .interactiveDismissDisabled(model?.isWorking == true)
        .task { [app] in
            guard model == nil, let user = app.user, user.canPrescribe else { return }
            if let task { model = task; return }
            let context = app.contextID
            let apiContext = await app.api.requestContextID()
            guard context == app.contextID else { return }
            let created = LARIPrescriptionTask(command: command, api: app.api, context: apiContext, user: user, isContextCurrent: { [weak app] in app?.contextID == context && app?.user?.id == user.id && app?.user?.canPrescribe == true })
            model = created; onTaskReady?(created)
            await created.searchPatients()
            await created.searchMedicines()
            await recoverSession()
        }
        .navigationDestination(isPresented: $openReview) {
            if let model, let patient = model.patient, let document = model.document {
                ClinicalDocumentDetailView(patient: patient, kind: .prescription, documentID: document.serverID, existingReview: model.signatureReview)
            }
        }
    }

    private func content(_ model: LARIPrescriptionTask) -> some View {
        @Bindable var form = model
        return Form {
            Section {
                Text("Vou preparar o rascunho e levar você à assinatura.").font(.headline)
                Text("Confirme o paciente e o medicamento. Os dados clínicos que não estiverem no pedido precisam ser preenchidos por você.").font(.subheadline).foregroundStyle(.secondary)
                DisclosureGroup("Seu pedido original") { Text(model.command.original).textSelection(.enabled) }
            }
            if model.document == nil {
                Section("Paciente") {
                    if let patient = model.patient {
                        patientIdentity(patient)
                        Button("Escolher outro paciente") { Task { await model.searchPatients(); await recoverSession() } }.disabled(!model.canEdit)
                    }
                    TextField("Nome do paciente", text: $form.patientQuery)
                    Button("Buscar paciente") { Task { await model.searchPatients(); await recoverSession() } }.disabled(!model.canEdit || model.patientQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    ForEach(model.patients) { patient in
                        Button { Task { await model.selectPatient(patient); await recoverSession() } } label: { patientIdentity(patient) }.disabled(!model.canEdit)
                    }
                    if model.hasMorePatients { Text("Há mais resultados. Refine o nome para localizar o paciente certo.").font(.footnote) }
                }
                Section {
                    TextField("Buscar medicamento no catálogo", text: $form.medicineQuery)
                    Button("Consultar catálogo") { Task { await model.searchMedicines(); await recoverSession() } }.disabled(!model.canEdit || model.medicineQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    ForEach(model.medicines) { medicine in
                        Button { Task { model.selectMedicine(medicine); await model.checkMedicineControl(); await recoverSession() } } label: { medicineIdentity(medicine) }.disabled(!model.canEdit)
                    }
                    if let medicine = model.selectedMedicine {
                        medicineIdentity(medicine)
                        TextField("Medicamento e concentração da receita", text: $form.medicine, axis: .vertical)
                            .disabled(model.catalogPresentationIsFixed || !model.canEdit)
                        if !model.medicineMatchesSelection {
                            Text("O nome da receita precisa corresponder ao produto selecionado. Para trocar o medicamento, escolha outro resultado do catálogo.").font(.footnote).foregroundStyle(.red)
                        }
                        if !model.command.medicineQuery.isEmpty {
                            Text("No pedido: \(model.command.medicineQuery). Confira qualquer diferença de apresentação ou concentração antes de prosseguir.").font(.footnote).foregroundStyle(.secondary)
                        }
                        if let control = model.medicineControl {
                            LabeledContent("Modelo informado pelo sistema", value: control.modelo?.replacingOccurrences(of: "_", with: " ") ?? "Não identificado")
                            if let list = control.lista { LabeledContent("Lista de controle", value: list) }
                            if !control.supported || !model.controlMatchesCatalog {
                                Text("O modelo não foi identificado ou exige um receituário especial com dados adicionais. Este atalho não cria essa receita; use o fluxo clínico completo.").font(.footnote).foregroundStyle(.orange)
                            }
                        }
                        Button("Conferir controle do medicamento") { Task { await model.checkMedicineControl(); await recoverSession() } }.disabled(!model.canEdit)
                    }
                } header: { Text("Medicamento") } footer: {
                    Text("O catálogo ajuda a identificar o produto. Confira a apresentação e a concentração prescritas. Concentração não define dose, frequência nem quantidade.")
                }
                if model.selectedMedicine != nil {
                    Section("Complete a prescrição") {
                        Picker("Tipo de receita", selection: $form.prescriptionType) {
                            Text("Selecione após conferir").tag("")
                            Text("Comum").tag("comum")
                            Text("Controle especial").tag("controle_especial")
                            Text("Antimicrobiano").tag("antimicrobiano")
                        }
                        if let control = model.medicineControl, !form.prescriptionType.isEmpty, !control.supports(type: form.prescriptionType) {
                            Text("O tipo precisa ser compatível com o modelo consultado. Receituários especiais não estão disponíveis neste atalho.").font(.footnote).foregroundStyle(.red)
                        }
                        TextField("Posologia: dose, via e frequência", text: $form.posology, axis: .vertical)
                        TextField("Quantidade a dispensar", text: $form.quantity)
                        Toggle("Uso contínuo", isOn: $form.continuous)
                        TextField("Período informado", text: $form.duration)
                    }.disabled(!model.canEdit)
                }
                if let allergies = model.allergies {
                    Section("Alergias atuais do prontuário") {
                        if allergies.isEmpty { Text("Nenhuma alergia foi retornada nesta consulta ao prontuário.").font(.footnote) }
                        ForEach(Array(allergies.enumerated()), id: \.offset) { _, allergy in
                            Label("\(allergy.substancia) — \(allergy.severidade)", systemImage: "exclamationmark.triangle")
                            if let reaction = allergy.reacao { Text(reaction).font(.footnote) }
                        }
                        if !allergies.isEmpty { Text("Este atalho não envia justificativa para substituir um alerta de alergia. Caso o serviço bloqueie a receita, revise a conduta no fluxo clínico completo.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Toggle("Conferi paciente, apresentação, tipo, posologia, quantidade e alergias", isOn: $form.reviewed).disabled(!model.canEdit)
                    Button {
                        Task {
                            await model.createDraft(); await recoverSession()
                            if model.document != nil { openReview = true }
                        }
                    } label: { Label("Preparar para assinatura", systemImage: "signature") }.disabled(!model.canCreate)
                } footer: { Text("Esta etapa salva somente o rascunho. Antes da assinatura, você verá novamente o conteúdo e os contatos atuais. A assinatura inicia o envio pelo serviço.") }
            } else if let document = model.document {
                Section {
                    Label("Rascunho localizado no sistema", systemImage: "checkmark.circle")
                    Text(document.detail).textSelection(.enabled)
                    Button("Revisar documento e assinatura") { openReview = true }
                }
            }
            Section {
                if model.busy { ProgressView("Consultando o sistema…") }
                WriteStatus(outcome: model.outcome, error: model.error)
                if model.outcome == .uncertain {
                    Button("Conferir se o rascunho foi salvo") { Task { await model.reconcileDraft(); await recoverSession() } }.disabled(model.busy)
                    if let patient = model.patient {
                        NavigationLink("Consultar documentos do paciente") { PatientDocumentsView(patient: patient) }
                    }
                    Text("O pedido não será reenviado automaticamente. A conferência faz apenas uma leitura pelo identificador deste rascunho.").font(.footnote)
                }
            }
        }
    }
    private func patientIdentity(_ patient: Patient) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(patient.nome).font(.headline)
            if let birth = patient.nascimento { Text("Nascimento: \(birth)").font(.caption) }
            if let cpf = patient.cpfMascarado { Text("CPF: \(cpf)").font(.caption) }
            if patient.nascimento == nil && patient.cpfMascarado == nil { Text("Confira a identidade no cadastro antes de prosseguir.").font(.caption) }
        }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func medicineIdentity(_ medicine: MedicineMatch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(medicine.nomeProduto).font(.headline)
            if let active = medicine.principioAtivo { Text(active) }
            if let concentration = medicine.concentracao { Text("Concentração no catálogo: \(concentration)") }
            if let form = medicine.formaFarmaceutica { Text(form) }
            if let regulation = medicine.categoriaRegulatoria { Text("Categoria: \(regulation)") }
            if let company = medicine.empresa { Text(company) }
            if let source = medicine.fonte { Text("Fonte: \(source)") }
        }.font(.footnote).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func recoverSession() async {
        if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) }
    }
}
