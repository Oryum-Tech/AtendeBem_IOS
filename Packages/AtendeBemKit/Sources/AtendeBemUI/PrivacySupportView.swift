import SwiftUI

/// Factual information about this client; the service policy remains available separately.
struct PrivacySupportView: View {
    var body: some View {
        List {
            Section("Seus dados no aplicativo") {
                Text("O aplicativo acessa os serviços do AtendeBem por conexão HTTPS. As informações disponíveis dependem da sua conta e das permissões da clínica.")
                Text("As credenciais de sessão ficam no Keychain do sistema. Esta versão não mantém uma cópia do prontuário em arquivos para uso sem internet.")
                Text("Cadastros, alergias, agendamentos, rascunhos clínicos e documentos que você salva são enviados aos serviços da clínica. PDFs são carregados para visualização. Preferências de navegação ficam no aparelho.")
                Text("Consultas pausadas ficam somente na memória desta sessão do aplicativo. Para continuar em outro dispositivo ou depois de encerrar o app, salve o rascunho no servidor. Sair da conta, trocar de clínica ou atualizar os acessos descarta as anotações locais; uma gravação incerta precisa ser conferida no servidor antes de ser repetida.")
                Text("Ao compartilhar um PDF, você escolhe o destino na folha de compartilhamento do sistema. O destinatário ou aplicativo escolhido receberá uma cópia que não poderá ser revogada pelo AtendeBem.")
                Text("Ao usar a conversa ou as sugestões com IA da LARI, o texto informado e, quando selecionado, o identificador do paciente são enviados ao serviço de inteligência artificial do AtendeBem. Consulte as condições de privacidade da clínica antes de incluir dados pessoais.")
                Text("A LARI utiliza Anthropic (Claude) e Google (Gemini), conforme a configuração do serviço. Esses provedores processam o texto enviado para gerar respostas. A tela da LARI solicita sua autorização antes do envio. Não inclua informações que identifiquem pacientes no chat geral.")
                Text("As tarefas da LARI usam os serviços autorizados da clínica. Abrir uma tarefa não envia automaticamente seu pedido ao chat com IA. Confira paciente, clínica, período e conteúdo antes de confirmar uma operação. A consulta de informações depende das permissões da sua conta.")
                Text("A transcrição é opcional. Antes de gravar, confirme a autorização dos participantes. O acesso ao microfone é solicitado pelo iOS quando você inicia a gravação. O áudio só é enviado para transcrição após sua autorização específica; o serviço utiliza Google Gemini. Revise a transcrição antes de usá-la na consulta. A retenção nos serviços e no provedor segue suas próprias políticas.")
                Text("Antes de assinar uma receita, confira o conteúdo e os contatos do paciente. A assinatura solicita o envio pelo serviço aos canais cadastrados. A confirmação da assinatura não comprova que a mensagem foi entregue ao paciente.")
                Text("Ao gerar um resumo para preparar a consulta, o serviço consulta o prontuário autorizado e pode enviar fatos estruturados aos provedores de IA. A geração depende da sua autorização nessa tela. O resumo não é salvo automaticamente como evolução; fatos e trechos originais são apresentados para conferência.")
                ServiceLink("Privacidade da Anthropic", systemImage: "arrow.up.right.square", address: "https://www.anthropic.com/legal/privacy")
                ServiceLink("Privacidade do Google", systemImage: "arrow.up.right.square", address: "https://policies.google.com/privacy")
                Text("Mensagens da equipe são enviadas aos serviços da clínica. Publicações e interações na comunidade são compartilhadas conforme a visibilidade selecionada. Não publique informações que identifiquem pacientes.")
                Text("Ao sair da conta, o aplicativo remove sua sessão e os dados carregados da interface. Isso não exclui sua conta nem os registros mantidos pela clínica.")
            }
            Section("Políticas do serviço") {
                ServiceLink("Política de privacidade", systemImage: "hand.raised", address: "https://www.atendebem.io/legal/privacidade")
                ServiceLink("Termos de uso", systemImage: "doc.text", address: "https://www.atendebem.io/legal/termos")
            }
            Section("Fale com a equipe") {
                ServiceLink("Suporte: contato@atendebem.io", systemImage: "envelope", address: "mailto:contato@atendebem.io")
                ServiceLink("Privacidade: privacidade@atendebem.io", systemImage: "hand.raised", address: "mailto:privacidade@atendebem.io")
                Text("Para pedir ajuda, informe a versão do aplicativo e descreva o problema. Não envie senhas, códigos de verificação ou prontuários por e-mail.")
                    .foregroundStyle(.secondary)
            }
            Section("Direitos sobre seus dados") {
                Text("Solicitações sobre dados da conta podem ser encaminhadas ao canal de privacidade. Para informações clínicas, procure também a clínica responsável pelo atendimento.")
                Text("Encerrar o acesso e excluir registros clínicos são procedimentos diferentes. A guarda de determinados registros pode ser exigida por lei.")
            }
        }
        .navigationTitle("Privacidade e suporte")
        .inlineTitle()
        .accessibilityIdentifier("privacy.support")
    }
}

struct ClinicalSafetyView: View {
    var body: some View {
        List {
            Section("Informações para o cuidado") {
                Text("O aplicativo exibe informações registradas nos serviços da clínica. Confirme a identidade do paciente, o contexto do atendimento e a data de atualização antes de usar os dados.")
                Text("Informação ausente sobre alergias não significa ausência de alergias. Confirme essa informação com o paciente e no registro clínico.")
            }
            Section("Medicamentos") {
                Text("Profissionais autorizados podem registrar receitas e solicitar sua assinatura pelo serviço. Revise paciente, medicamento, dose, via e orientações antes de assinar. Um rascunho salvo não é uma receita assinada.")
                Text("O aplicativo não calcula doses nem vende medicamentos. A escolha da terapêutica cabe ao profissional habilitado, com consulta às fontes oficiais e às regras aplicáveis ao tipo de receita.")
                Text("A consulta de interações usa uma base limitada de princípios ativos. Confira a fonte e a data de revisão de cada alerta. Nenhum alerta encontrado não garante ausência de interação ou segurança da combinação; a consulta não avalia dose, condições clínicas ou todas as alergias do paciente.")
            }
            Section("Rascunhos e sugestões") {
                Text("Salvar uma evolução como rascunho não assina o prontuário nem conclui o agendamento. Sugestões da LARI podem conter erros e precisam de revisão profissional antes de integrar o registro clínico.")
            }
            Section("Urgências") {
                Text("O aplicativo não é um canal de atendimento de emergência. Em uma emergência no Brasil, procure o serviço de emergência ou ligue 192.")
            }
        }
        .navigationTitle("Uso das informações")
        .inlineTitle()
    }
}

private struct ServiceLink: View {
    let title: String
    let systemImage: String
    let address: String

    init(_ title: String, systemImage: String, address: String) {
        self.title = title
        self.systemImage = systemImage
        self.address = address
    }

    var body: some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                Label(title, systemImage: systemImage).frame(minHeight: 44, alignment: .leading)
            }
        }
    }
}
