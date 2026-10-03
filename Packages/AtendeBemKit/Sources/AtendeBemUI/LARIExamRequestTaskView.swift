import AtendeBemCore
import SwiftUI

struct LARIExamRequestTaskView: View {
    let command: String
    var task: LARIExamRequestTask? = nil
    var onTaskReady: ((LARIExamRequestTask) -> Void)? = nil
    @Environment(AppState.self) private var app
    @State private var model: LARIExamRequestTask?
    @State private var confirmCreate = false
    @State private var confirmSend = false
    @State private var openDocument = false
    var body: some View {
        Group {
            if app.user?.canRequestExam != true { RestrictedState() }
            else if let model { content(model) }
            else { ProgressView("Preparando solicitação de exames…") }
        }.navigationTitle("Exames com LARI").inlineTitle()
            .interactiveDismissDisabled(model?.isWorking == true)
            .task { [app] in
                guard model == nil, let user = app.user, user.canRequestExam else { return }
                if let task { model = task; return }
                let context = app.contextID, apiContext = await app.api.requestContextID()
                guard context == app.contextID else { return }
                let created = LARIExamRequestTask(command: command, api: app.api, context: apiContext, user: user,
                    isContextCurrent: { [weak app] in app?.contextID == context && app?.user?.id == user.id && app?.user?.canRequestExam == true })
                model = created; onTaskReady?(created); await created.searchPatients(); await recover()
            }
            .navigationDestination(isPresented: $openDocument) {
                if let model, let patient = model.lookup.patient, let document = model.document {
                    ClinicalDocumentDetailView(patient: patient, kind: .exam, documentID: document.id, existingReview: model.signatureReview)
                }
            }
            .confirmationDialog("Emitir esta solicitação de exames?", isPresented: $confirmCreate, titleVisibility: .visible) {
                Button("Emitir e solicitar assinatura") { Task { await model?.create(); await recover() } }
                Button("Voltar à revisão", role: .cancel) {}
            } message: {
                Text("O pedido será registrado e o serviço tentará assiná-lo com seu certificado. Confira todos os exames, indicação e paciente antes de confirmar. Esta etapa não envia a requisição ao paciente.")
            }
            .confirmationDialog("Solicitar envio desta requisição?", isPresented: $confirmSend, titleVisibility: .visible) {
                Button("Solicitar envio aos contatos revisados") { Task { await model?.send(); await recover() } }
                Button("Voltar à revisão", role: .cancel) {}
            } message: { Text("O documento e os contatos serão conferidos novamente. A confirmação registra um pedido de envio; ela não comprova recebimento pelo paciente.") }
    }
    private func content(_ model: LARIExamRequestTask) -> some View {
        @Bindable var form = model
        return Form {
            LARITaskContextSection(command: command, explanation: "Vou preparar apenas os exames que você solicitar. Você revisa o pedido completo antes da emissão e da tentativa de assinatura.")
            if let document = model.document {
                Section {
                    if let patient = model.lookup.patient { LARIPatientIdentity(patient: patient) }
                    Text(ClinicalDocumentSnapshot(document).detail).textSelection(.enabled)
                    Label(ClinicalDocumentSnapshot(document).signatureLabel, systemImage: "signature")
                    Button("Abrir documento e conferir assinatura") { openDocument = true }.disabled(model.isWorking)
                    Button("Atualizar assinatura e preparar envio") { Task { await model.prepareDelivery(); await recover() } }.disabled(model.isWorking)
                } header: { Text("Solicitação registrada") } footer: { Text("A assinatura e o envio são etapas distintas. Atualize a requisição depois de assinar para conferir a situação antes de enviar.") }
                if let delivery = model.delivery {
                    Section {
                        Text(delivery.name).font(.headline)
                        LabeledContent("WhatsApp cadastrado", value: delivery.phone ?? "Não informado")
                        LabeledContent("E-mail cadastrado", value: delivery.email ?? "Não informado")
                        Toggle("Enviar pelo WhatsApp", isOn: $form.sendByWhatsApp).disabled(delivery.phone == nil || !model.deliveryOutcome.canSubmit || model.isWorking)
                        Toggle("Enviar por e-mail", isOn: $form.sendByEmail).disabled(delivery.email == nil || !model.deliveryOutcome.canSubmit || model.isWorking)
                        Toggle("Conferi documento, paciente, contatos e canais", isOn: $form.deliveryReviewed).disabled(!model.deliveryOutcome.canSubmit || model.isWorking)
                        if document.assinatura?.padrao != "ICP-Brasil" {
                            Text("O envio por este fluxo exige a assinatura ICP-Brasil confirmada pelo serviço. Abra o documento para concluir ou conferir a assinatura.").font(.footnote)
                        }
                        Button("Solicitar envio da requisição") { confirmSend = true }.disabled(!model.canSend)
                        WriteStatus(outcome: model.deliveryOutcome, error: model.deliveryError)
                        if model.deliveryOutcome == .succeeded { Label("Envio solicitado ao serviço", systemImage: "checkmark.circle") }
                        if model.deliveryOutcome == .uncertain { Text("O serviço pode ter recebido o pedido de envio. Não há comprovante de entrega nesta tela; o envio não será repetido automaticamente.").font(.footnote) }
                    } header: { Text("Entregar ao paciente") } footer: { Text("Se um contato estiver incorreto, atualize o cadastro antes de enviar. A resposta de envio enfileirado não comprova entrega.") }
                } else if let error = model.deliveryError { Section { Text(error).foregroundStyle(.red) } }
            } else {
                LARIPatientTaskSection(lookup: model.lookup, editable: model.canEdit, search: model.searchPatients, select: model.selectPatient, change: model.changePatient)
                Section("Pedido de exames") {
                    Picker("Tipo", selection: $form.type) {
                        Text("Selecione após revisar").tag("")
                        Text("Laboratorial").tag("laboratorial"); Text("Imagem").tag("imagem"); Text("Outro").tag("outro")
                    }
                    TextField("Indicação clínica, se pertinente", text: $form.indication, axis: .vertical).lineLimit(3...8)
                    ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 5) {
                            TextField("Descrição do exame", text: Binding(get: { model.items.indices.contains(index) ? model.items[index].descricao : "" }, set: { model.updateItemDescription(at: index, text: $0) }), axis: .vertical).font(.headline)
                            if let tuss = item.tuss { Text("TUSS: \(tuss)").font(.caption) }
                            Button("Remover este exame", role: .destructive) { model.removeItem(at: index) }
                        }
                    }
                    if let validation = model.itemValidationMessage { Text(validation).font(.footnote).foregroundStyle(.red) }
                    TextField("Nome completo do exame", text: $form.itemDescription, axis: .vertical)
                    TextField("TUSS, se conhecido (opcional)", text: $form.itemTUSS)
                    Button("Adicionar exame à lista") { model.addItem() }.disabled(model.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.disabled(!model.canEdit)
                Section {
                    Toggle("Revisei paciente, exames e indicação e autorizo a emissão e a tentativa de assinatura", isOn: $form.reviewed).disabled(!model.canEdit)
                    Button("Revisar emissão e assinatura") { confirmCreate = true }.disabled(!model.canCreate)
                } footer: { Text("Ao emitir, o serviço já tenta usar seu certificado. Não é apenas um rascunho. Nenhum envio ao paciente ocorre nesta etapa.") }
            }
            Section {
                if model.busy { ProgressView("Conferindo o sistema…") }
                WriteStatus(outcome: model.outcome, error: model.error)
                if model.outcome == .uncertain {
                    Button("Consultar pedidos do paciente") { Task { await model.consultExistingRequests(); await recover() } }.disabled(model.isWorking)
                    Text("Os pedidos abaixo são referências para conferência. Um pedido parecido não comprova o resultado desta tentativa. Não será criado outro automaticamente.").font(.footnote)
                    ForEach(model.existingRequests) { request in
                        DisclosureGroup("\(request.itens.count) exame(s) · \(request.status)") {
                            ClinicalTimestamp(label: "Criado", value: request.criadoEm)
                            Text(ClinicalDocumentSnapshot(request).detail).textSelection(.enabled)
                            Text("Identificador: \(request.id)").font(.caption).textSelection(.enabled)
                            Text(ClinicalDocumentSnapshot(request).signatureLabel).font(.caption)
                        }
                    }
                }
            }
        }
    }
    private func recover() async { if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) } }
}
