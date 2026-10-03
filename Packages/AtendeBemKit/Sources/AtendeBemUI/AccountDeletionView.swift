import SwiftUI
import AtendeBemCore
#if canImport(MessageUI) && os(iOS)
import MessageUI
#endif

struct AccountDeletionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var mailRequest: MailRequest?
    @State private var outcome: MailOutcome?

    private var draft: AccountDeletionDraft? {
        guard app.phase == .ready, let user = app.user else { return nil }
        return try? AccountDeletionDraft(accountID: user.id, accountEmail: user.email)
    }

    var body: some View {
        Form {
            if let draft {
                Section {
                    Label("Solicitar exclusão da conta", systemImage: "person.crop.circle.badge.minus")
                        .font(.headline)
                    Text("Você pode iniciar aqui o pedido de exclusão da sua conta AtendeBem. A equipe de privacidade recebe o pedido por e-mail e poderá precisar confirmar sua identidade.")
                    Text("O pedido abrange sua conta e seus dados pessoais, inclusive o acesso às diferentes clínicas. Não se limita à clínica selecionada.")
                }
                Section("Conta que será informada no pedido") {
                    LabeledContent("E-mail", value: draft.accountEmail)
                    LabeledContent("Identificador", value: draft.accountID)
                        .textSelection(.enabled)
                }
                Section("Antes de continuar") {
                    Text("Solicitar a exclusão não encerra a conta imediatamente. Peça à equipe a confirmação de recebimento e o prazo de processamento; este aplicativo não acompanha a conclusão do atendimento.")
                    Text("Prontuários e outros registros clínicos podem ter guarda obrigatória sob responsabilidade da clínica. O pedido solicita a exclusão dos dados que não precisem ser mantidos e a informação sobre eventuais retenções.")
                    Text("Não envie senhas, códigos de verificação, documentos de pacientes ou prontuários neste e-mail.")
                        .foregroundStyle(.secondary)
                }
                if let outcome {
                    Section {
                        Label(outcome.title, systemImage: outcome.symbol).font(.headline)
                        Text(outcome.detail)
                    }.accessibilityIdentifier("account.deletion.outcome")
                }
                Section {
                    Button(action: prepareMessage) {
                        Label("Solicitar exclusão por e-mail", systemImage: "envelope")
                            .frame(minHeight: 44, alignment: .leading)
                    }.accessibilityIdentifier("account.deletion.prepare")
                } footer: {
                    Text("Você revisa a mensagem e confirma o envio no seu aplicativo de e-mail. Abrir ou salvar um rascunho não comprova que a equipe recebeu o pedido.")
                }
                Section("Mensagem para o canal de privacidade") {
                    Text(AccountDeletionDraft.recipient).textSelection(.enabled)
                    DisclosureGroup("Revisar mensagem") {
                        Text(AccountDeletionDraft.subject).font(.headline).textSelection(.enabled)
                        Text(draft.body).textSelection(.enabled)
                    }
                    Text("Se não houver um aplicativo de e-mail configurado, você pode selecionar e copiar a mensagem para enviar ao endereço acima.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Consultar privacidade e suporte") { PrivacySupportView() }
                }
            } else {
                ContentUnavailableView("Conta indisponível", systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Volte à sua conta e confira o acesso antes de preparar o pedido. O canal de privacidade também está disponível em Privacidade e suporte."))
                NavigationLink("Privacidade e suporte") { PrivacySupportView() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Excluir minha conta")
        .inlineTitle()
        .accessibilityIdentifier("account.deletion")
        .onChange(of: app.contextID) { _, _ in clearPreparedMessage() }
        .onChange(of: app.user?.id) { _, _ in clearPreparedMessage() }
        .onChange(of: app.user?.email) { _, _ in clearPreparedMessage() }
        .onChange(of: app.phase) { _, phase in if phase != .ready { clearPreparedMessage() } }
        .sheet(item: $mailRequest) { request in
            if isCurrent(request) {
                #if canImport(MessageUI) && os(iOS)
                AccountDeletionMailComposer(draft: request.draft) { result in
                    guard isCurrent(request) else { return }
                    outcome = result
                    mailRequest = nil
                }
                #endif
            }
        }
    }

    private func prepareMessage() {
        guard let draft, app.phase == .ready else { return }
        let request = MailRequest(draft: draft, contextID: app.contextID)
        outcome = nil
        #if canImport(MessageUI) && os(iOS)
        if MFMailComposeViewController.canSendMail() {
            mailRequest = request
            return
        }
        #endif
        guard let url = draft.mailtoURL else { outcome = .unavailable; return }
        openURL(url) { accepted in
            guard isCurrent(request) else { return }
            outcome = accepted ? .openedExternalApp : .unavailable
        }
    }

    private func isCurrent(_ request: MailRequest) -> Bool {
        app.phase == .ready && app.contextID == request.contextID && draft == request.draft
    }

    private func clearPreparedMessage() { mailRequest = nil; outcome = nil }

    private struct MailRequest: Identifiable {
        let id = UUID()
        let draft: AccountDeletionDraft
        let contextID: UUID
    }
}

private enum MailOutcome {
    case cancelled, saved, acceptedForSending, failed, openedExternalApp, unavailable
    var title: String {
        switch self {
        case .cancelled: "Envio cancelado"
        case .saved: "Rascunho salvo no Mail"
        case .acceptedForSending: "Mensagem encaminhada ao Mail"
        case .failed: "Não foi possível enviar"
        case .openedExternalApp: "Continue no seu aplicativo de e-mail"
        case .unavailable: "E-mail não disponível neste aparelho"
        }
    }
    var detail: String {
        switch self {
        case .cancelled: "Você encerrou a mensagem sem confirmar o envio. Nenhuma exclusão foi realizada por esta tela."
        case .saved: "O rascunho foi salvo, mas ainda precisa ser enviado. Não há confirmação de recebimento pela equipe de privacidade."
        case .acceptedForSending: "O Mail aceitou a mensagem para envio. Aguarde a confirmação da equipe de privacidade. Isso não confirma o recebimento nem a exclusão da conta."
        case .failed: "O Mail informou uma falha. Confira a caixa de saída antes de tentar novamente para evitar mensagens duplicadas. A exclusão não foi confirmada."
        case .openedExternalApp: "Revise a mensagem e confirme o envio por lá. O AtendeBem não consegue confirmar o envio ou o recebimento pelo canal de privacidade."
        case .unavailable: "Configure um aplicativo de e-mail ou copie a mensagem abaixo para enviar a privacidade@atendebem.io. Nenhum pedido foi enviado por esta tela."
        }
    }
    var symbol: String {
        switch self {
        case .failed, .unavailable: "exclamationmark.circle"
        case .cancelled: "xmark.circle"
        case .saved: "doc"
        case .acceptedForSending, .openedExternalApp: "envelope"
        }
    }
}

#if canImport(MessageUI) && os(iOS)
private struct AccountDeletionMailComposer: UIViewControllerRepresentable {
    let draft: AccountDeletionDraft
    let onFinish: (MailOutcome) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([AccountDeletionDraft.recipient])
        controller.setSubject(AccountDeletionDraft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MailOutcome) -> Void
        init(onFinish: @escaping (MailOutcome) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            guard error == nil else { onFinish(.failed); return }
            switch result {
            case .cancelled: onFinish(.cancelled)
            case .saved: onFinish(.saved)
            case .sent: onFinish(.acceptedForSending)
            case .failed: onFinish(.failed)
            @unknown default: onFinish(.failed)
            }
        }
    }
}
#endif
