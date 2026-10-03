import SwiftUI
import AtendeBemCore

struct MoreView: View {
    @Environment(AppState.self) private var app
    @State private var search = ""
    private var entries: [MoreFeature] {
        MoreFeature.allCases.filter { $0.allowed(app.user) && (search.isEmpty || $0.searchText.localizedStandardContains(search)) }
    }
    var body: some View {
        List {
            ForEach(["Atendimento", "Conexões e gestão", "Meu aplicativo"], id: \.self) { group in
                let matches = entries.filter { $0.group == group }
                if !matches.isEmpty {
                    Section(group) {
                        ForEach(matches) { entry in
                            NavigationLink { destination(entry) } label: {
                                FeatureRow(title: entry == .patients && app.user?.canReadClinicalData != true ? "Pacientes" : entry.title,
                                           detail: entry == .patients && app.user?.canReadClinicalData != true ? "Cadastro e contato, conforme seu acesso" : entry.detail,
                                           symbol: entry.symbol)
                            }
                                .accessibilityIdentifier("more.\(entry.rawValue)")
                        }
                    }
                }
            }
            if entries.isEmpty { ContentUnavailableView.search(text: search) }
        }.navigationTitle("Mais").tint(Brand.accent).searchable(text: $search, prompt: "Buscar uma função")
    }
    @ViewBuilder private func destination(_ feature: MoreFeature) -> some View {
        switch feature {
        case .agenda: AgendaView(); case .patients: PatientsView(); case .lari: LARIChatView(); case .templates: ClinicalTemplatesView()
        case .team: TeamChatView(); case .community: CommunityView(); case .reports: ReportsView(); case .finance: FinancialDashboardView()
        case .settings: SettingsView(); case .updates: UpdatesView(); case .techbem: TechbemView()
        }
    }
}

private enum MoreFeature: String, CaseIterable, Identifiable {
    case agenda, patients, lari, templates, team, community, reports, finance, settings, updates, techbem
    var id: String { rawValue }
    var title: String {
        switch self {
        case .agenda: "Agenda"; case .patients: "Pacientes e prontuários"; case .lari: "LARI"; case .templates: "Modelos clínicos"
        case .team: "Chat da equipe"; case .community: "Comunidade médica"; case .reports: "Relatórios"; case .finance: "Financeiro"
        case .settings: "Configurações"; case .updates: "Novidades"; case .techbem: "Techbem · Meu Prontuário"
        }
    }
    var detail: String {
        switch self {
        case .agenda: "Horários, chegada e atendimento"; case .patients: "Ficha, histórico e consulta"; case .lari: "Receitas, relatórios e conversa com a assistente"
        case .templates: "Receitas, exames, protocolos e orientações"; case .team: "Mensagens internas da clínica"; case .community: "Publicações, colegas e conversas"
        case .reports: "Resultados por período"; case .finance: "Resumo e lançamentos da clínica"; case .settings: "Conta, clínica, aparência e documentos"; case .updates: "O que mudou nesta versão"; case .techbem: "Conheça o aplicativo para o paciente"
        }
    }
    var group: String {
        switch self { case .agenda, .patients, .lari, .templates: "Atendimento"; case .team, .community, .reports, .finance: "Conexões e gestão"; case .settings, .updates, .techbem: "Meu aplicativo" }
    }
    var symbol: String {
        switch self {
        case .agenda: "calendar"; case .patients: "person.2"; case .lari: "sparkles"; case .templates: "doc.on.doc"
        case .team: "bubble.left.and.bubble.right"; case .community: "person.3.sequence"; case .reports: "chart.bar.xaxis"; case .finance: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"; case .updates: "sparkles"; case .techbem: "heart.text.clipboard"
        }
    }
    var searchText: String {
        title + " " + detail + " " + (self == .settings ? "preferencias certificado privacidade ajuda atalhos" : "")
            + (self == .techbem ? " meuprontuario remedios receitas exames lembretes app paciente compartilhar indicar" : "")
    }
    func allowed(_ user: User?) -> Bool {
        switch self {
        case .agenda: user?.canReadAgenda == true; case .patients: user?.canReadPatients == true; case .lari: user?.canUseLARI == true
        case .templates: user?.canPrescribe == true; case .reports: user?.canReadReports == true; case .finance: user?.canReadFinancialReports == true
        case .team, .community, .settings, .updates, .techbem: user != nil
        }
    }
}

struct AccountView: View {
    @Environment(AppState.self) private var app
    @State private var confirmSignOut = false
    @State private var confirmRefresh = false
    var body: some View {
        Form {
            if let user = app.user {
                Section("Minha conta") {
                    LabeledContent("Nome", value: user.nome)
                    LabeledContent("E-mail", value: user.email)
                    LabeledContent("Clínica", value: app.clinicName)
                }
                Section("Acesso nesta clínica") {
                    ForEach(Array(Set(user.papeis)).sorted(), id: \.self) { Text(User.roleLabel($0)) }
                    if user.papeis.isEmpty { Text("Nenhum perfil foi atribuído nesta clínica.").foregroundStyle(.secondary) }
                    NavigationLink("Consultar meus perfis em outras clínicas") { ClinicsView() }
                }
                Section {
                    if user.canConfirmAppointment { Label("Agendar, reagendar e registrar chegada", systemImage: "calendar") }
                    else if user.canReadAgenda { Label("Consultar a agenda e a fila", systemImage: "calendar") }
                    if user.canCreatePatient { Label("Cadastrar pacientes", systemImage: "person.badge.plus") }
                    if user.canReadClinicalData { Label("Consultar o prontuário conforme seus vínculos", systemImage: "doc.text") }
                    if user.canPrescribe { Label("Preparar receitas e modelos clínicos", systemImage: "pills") }
                    if user.canIssueDocument { Label("Emitir atestados e documentos", systemImage: "doc.richtext") }
                    if user.containsAnyRole(["gestor", "contabilista", "admin"]) { Label("Consultar informações financeiras", systemImage: "chart.bar") }
                } header: { Text("Disponível para este perfil") } footer: {
                    Text("Seus perfis são definidos pela clínica. Quando há mais de um, os acessos se somam. A autorização de cada paciente e ação continua sendo conferida pelo serviço.")
                }
                Section {
                    if let updatedAt = app.accessUpdatedAt { LabeledContent("Acessos conferidos", value: updatedAt.formatted(date: .abbreviated, time: .shortened)) }
                    Button("Atualizar meus acessos") { confirmRefresh = true }
                } footer: {
                    Text("Use após a clínica alterar seus perfis ou vínculos. O aplicativo consulta novamente sua conta e suas clínicas.")
                }
            }
            if app.user != nil {
                Section {
                    NavigationLink { AccountDeletionView() } label: {
                        Label("Excluir minha conta", systemImage: "person.crop.circle.badge.minus")
                            .frame(minHeight: 44, alignment: .leading)
                    }.accessibilityIdentifier("account.deletion.open")
                } footer: { Text("Inicie um pedido de exclusão com a equipe de privacidade.") }
            }
            Section { Button("Sair da conta", role: .destructive) { confirmSignOut = true }.frame(minHeight: 44) }
        }.formStyle(.grouped).navigationTitle("Minha conta").inlineTitle()
            .confirmationDialog("Sair desta conta?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sair da conta", role: .destructive) { Task { await app.signOut() } }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Consultas pausadas e alterações ainda não salvas neste aplicativo serão descartadas. Os rascunhos já salvos no servidor continuam disponíveis. Se uma gravação ficou sem confirmação, confira o histórico ao entrar novamente antes de repetir o registro.")
            }
            .confirmationDialog("Atualizar os acessos e voltar ao início?", isPresented: $confirmRefresh, titleVisibility: .visible) {
                Button("Atualizar acessos") { Task { await app.loadContext() } }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("As telas abertas serão recarregadas. Salve qualquer edição em andamento antes de continuar.") }
    }
}

struct ClinicsView: View {
    @Environment(AppState.self) private var app
    @State private var search = ""
    @State private var pending: Clinic?
    @State private var confirmSwitch = false
    private var visibleClinics: [Clinic] {
        app.clinics.filter { search.isEmpty || ($0.nome + " " + $0.papeis.map(User.roleLabel).joined(separator: " ")).localizedStandardContains(search) }
    }
    var body: some View {
        List {
            Section {
                ForEach(visibleClinics) { clinic in
                    Button { pending = clinic; confirmSwitch = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(clinic.nome).font(.headline).foregroundStyle(.primary)
                                Text(clinic.papeis.map(User.roleLabel).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if clinic.id == app.activeClinicID { Image(systemName: "checkmark").accessibilityLabel("Clínica selecionada") }
                        }.frame(minHeight: 44)
                    }.disabled(clinic.id == app.activeClinicID || app.phase != .ready)
                }
                if visibleClinics.isEmpty { ContentUnavailableView.search(text: search) }
            } footer: { Text("Cada clínica tem sua própria equipe, agenda e permissões. A troca recarrega seus acessos e as informações dessa clínica; não reúne cadastros ou prontuários de clínicas diferentes.") }
        }.navigationTitle("Suas clínicas").inlineTitle()
            .searchable(text: $search, prompt: "Buscar clínica ou perfil")
            .confirmationDialog("Abrir \(pending?.nome ?? "a clínica selecionada")?", isPresented: $confirmSwitch, titleVisibility: .visible) {
                Button("Trocar clínica") { if let pending { Task { await app.switchClinic(pending) } } }
                Button("Cancelar", role: .cancel) { pending = nil }
            } message: { Text("Seus perfis e dados serão atualizados para a clínica escolhida. Alterações não salvas em outras telas serão descartadas.") }
    }
}

struct UpdatesView: View {
    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Versão \(version) (\(build))"
    }

    var body: some View {
        List {
            Section(versionLabel) {
                Label("Tarefas da LARI com busca, abertura direta e situação de cada etapa", systemImage: "checklist")
                Label("Hoje com retomadas compactas e acesso direto à ficha do próximo paciente", systemImage: "person.text.rectangle")
                Label("Pedidos de bula com termo revisável e busca pelo teclado", systemImage: "magnifyingglass")
                Label("Medicamentos na LARI: busca, dados do registro e acesso ao Bulário oficial", systemImage: "pills")
                Label("Hoje destaca retomadas, o próximo agendamento e suas ações frequentes", systemImage: "sun.max")
                Label("LARI reúne tarefas de agenda, histórico e exames conforme seu perfil", systemImage: "checklist")
                Label("Transcrição opcional com autorização e revisão antes de usar na consulta", systemImage: "waveform")
                Label("Indicadores da clínica e interações com fontes e limites de cobertura", systemImage: "chart.xyaxis.line")
                Label("Pause uma consulta e continue pela Hoje nesta sessão do aplicativo", systemImage: "pause.circle")
                Label("Configurações preservam edições e avisam antes de descartar alterações", systemImage: "slider.horizontal.3")
                Label("LARI prepara receitas por comando, com conferência e assinatura profissional", systemImage: "signature")
                Label("LARI consulta o financeiro por período, conforme seu perfil", systemImage: "chart.bar.xaxis")
                Label("Fila com quem aguarda e quem está em atendimento", systemImage: "person.2")
                Label("Confirmação solicitada e resposta do paciente identificadas", systemImage: "checkmark.message")
                Label("Preparar consulta com resumo LARI, fatos e fontes", systemImage: "sparkles")
            }
            Section("Melhorias anteriores") {
                Label("Exames externos e resultados com acesso para a equipe autorizada", systemImage: "tray.and.arrow.down")
                Label("Laudos e arquivos com conferência do paciente antes de enviar", systemImage: "paperclip")
                Label("Procedência dos exames e ações próprias para solicitações da clínica", systemImage: "cross.vial")
                Label("LARI dentro da consulta com aplicação de trechos revisados", systemImage: "sparkles")
                Label("Receita, exame e atestado a partir da consulta confirmada", systemImage: "doc.badge.plus")
                Label("Abertura do documento criado e revisão antes da assinatura", systemImage: "doc.text.magnifyingglass")
                Label("Relatórios com períodos prontos, gráfico e valores exatos", systemImage: "chart.bar.xaxis")
                Label("Consulta com revisão e confirmação da evolução", systemImage: "checkmark.circle")
                Label("Alterações não salvas e comparação de rascunhos", systemImage: "square.and.pencil")
                Label("Triagens com queixa, risco registrado e medidas vinculadas", systemImage: "clipboard")
                Label("Acessos por perfil, clínica ativa e atalhos da recepção", systemImage: "person.badge.key")
                Label("Prontuário com problemas, sinais vitais e medicamentos de cada fonte", systemImage: "heart.text.clipboard")
                Label("Evoluções com queixa principal, seções e datas do registro", systemImage: "doc.text")
                Label("LARI com recuperação da sessão e contexto anterior revisável", systemImage: "sparkles")
                Label("Agenda da semana com visão dos horários e avisos por dia", systemImage: "calendar")
                Label("Filtros de pacientes por idade, acompanhamento e perfil clínico", systemImage: "line.3.horizontal.decrease")
                Label("Cópia privada e edição dos seus modelos clínicos", systemImage: "doc.on.doc")
                Label("Documentos do paciente com busca e filtro de assinatura", systemImage: "doc.text.magnifyingglass")
                Label("Configurações com busca ampliada e identificação das preferências locais", systemImage: "gearshape")
            }
            Section("Também no aplicativo") {
                Label("Atalhos da Hoje com navegação independente", systemImage: "square.grid.2x2")
                Label("Agenda com linha do tempo por hora e lista compacta", systemImage: "calendar")
                Label("Configurações organizadas, busca e aparência", systemImage: "gearshape")
                Label("Modelos de receitas e exames com revisão antes de salvar", systemImage: "doc.on.doc")
                Label("Vários exames em uma solicitação e padrão de letra das receitas", systemImage: "textformat.size")
                Label("Histórico unificado com registros anteriores e indicação de fontes indisponíveis", systemImage: "clock.arrow.circlepath")
                Label("Perfis profissionais, colegas e mensagens da comunidade", systemImage: "person.2")
                Label("Edição das próprias publicações e consulta de imagens", systemImage: "square.and.pencil")
                Label("Situação do certificado digital e compartilhamento de PDF", systemImage: "signature")
                Label("Atalhos personalizáveis para Receitas, Exames, Consulta e LARI", systemImage: "square.grid.2x2")
                Label("Conversa com a LARI e fontes da resposta", systemImage: "sparkles")
                Label("Chat interno da equipe e comunidade médica", systemImage: "bubble.left.and.bubble.right")
                Label("Relatórios de atendimentos e receitas por período", systemImage: "chart.bar")
                Label("Busca de medicamentos e CID-10", systemImage: "magnifyingglass")
                Label("História médica resumida com opção de expandir", systemImage: "text.alignleft")

                Label("Login e verificação em duas etapas", systemImage: "lock.shield")
                Label("Criação, reagendamento e acompanhamento de horários", systemImage: "calendar")
                Label("Cadastro de pacientes e registro de alergias", systemImage: "person.2")
                Label("Rascunhos clínicos com seções do prontuário", systemImage: "doc.text")
                Label("Receitas, documentos e pedidos de exames conforme seu perfil", systemImage: "doc.richtext")
                Label("Consulta de PDFs e assinaturas retornadas pelo serviço", systemImage: "signature")
                Label("Troca de clínica", systemImage: "building.2")
                Label("Privacidade e suporte antes e depois do login", systemImage: "hand.raised")
            }
            Section {
                Text("O aplicativo está em desenvolvimento e ainda não reúne todas as funções do AtendeBem. As ações disponíveis dependem das permissões e dos serviços da sua clínica.")
                    .foregroundStyle(.secondary)
            }
        }.navigationTitle("Novidades").inlineTitle()
    }
}

struct SyncInfoView: View {
    var body: some View {
        List {
            Section("Os mesmos dados da sua clínica") {
                Text("O aplicativo consulta os mesmos serviços da versão web. As telas mostram a hora da última atualização.")
                Text("Com o aplicativo aberto, a agenda em Dia e Lista, a fila e a lista de pacientes sem filtros são atualizadas periodicamente. Você também pode puxar para atualizar.")
                Text("A visão semanal mantém uma consulta recente por até cinco minutos. Buscas com filtros de pacientes são atualizadas ao mudar a busca, ao voltar ao aplicativo ou ao puxar para atualizar. Confira a hora mostrada na tela.")
            }
            Section("Quando a conexão falha") {
                Text("Os dados já carregados podem continuar visíveis com um aviso. Uma alteração só é confirmada depois que o servidor a aceita.")
                Text("Esta versão precisa de conexão para carregar e salvar informações. Não há gravações clínicas pendentes para envio posterior.")
            }
        }.navigationTitle("Atualização dos dados").inlineTitle()
    }
}
