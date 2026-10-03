import Foundation

public extension LARITaskRoute {
    static var tasks: [Self] { [.prescription, .appointment, .patientHistory, .examRequest, .transcription, .financial, .analytics, .interactions, .medicineReference] }
    static func availableTasks(for user: User, matching query: String = "") -> [Self] {
        let terms = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .split(whereSeparator: \.isWhitespace)
        return tasks.filter { route in
            guard route.isAllowed(for: user) else { return false }
            let searchable = "\(route.title) \(route.explanation) \(route.searchAliases)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            return terms.allSatisfy { searchable.contains($0) }
        }
    }
    private var searchAliases: String {
        switch self {
        case .prescription: "prescrição remédio"
        case .appointment: "agenda marcar"
        case .patientHistory: "prontuário antecedentes alergias"
        case .examRequest: "requisição pedido"
        case .transcription: "áudio gravação ditado"
        case .financial: "faturamento caixa"
        case .analytics: "demografia estatísticas"
        case .interactions: "interação farmacológica"
        case .medicineReference: "ANVISA registro indicação bulário"
        case .clarify, .conversation: ""
        }
    }
    var title: String {
        switch self {
        case .prescription: "Preparar receita"
        case .financial: "Relatório financeiro"
        case .appointment: "Agendar consulta"
        case .patientHistory: "Histórico do paciente"
        case .examRequest: "Solicitar exames"
        case .transcription: "Transcrever consulta"
        case .analytics: "Perfil e sazonalidade"
        case .interactions: "Interações de medicamentos"
        case .medicineReference: "Medicamentos e bulas"
        case .clarify: "Esclarecer pedido"
        case .conversation: "Conversar com LARI"
        }
    }
    var symbol: String {
        switch self {
        case .prescription: "pills"
        case .financial: "chart.bar.xaxis"
        case .appointment: "calendar.badge.plus"
        case .patientHistory: "clock.arrow.circlepath"
        case .examRequest: "cross.vial"
        case .transcription: "waveform"
        case .analytics: "chart.xyaxis.line"
        case .interactions: "cross.case"
        case .medicineReference: "book.closed"
        case .clarify: "questionmark.bubble"
        case .conversation: "sparkles"
        }
    }
    var starter: String {
        switch self {
        case .prescription: "Preparar receita de "
        case .appointment: "Agendar consulta para "
        case .patientHistory: "Consultar histórico do paciente "
        case .examRequest: "Solicitar exames de "
        case .transcription: "Transcrever consulta"
        case .financial: "Como foi o financeiro do mês anterior?"
        case .analytics: "Consultar sazonalidade dos atendimentos"
        case .interactions: "Consultar interações entre medicamentos"
        case .medicineReference: "Consultar medicamentos e bulas"
        case .clarify, .conversation: ""
        }
    }
    var explanation: String {
        switch self {
        case .prescription: "Paciente, medicamento e prescrição revisados antes da assinatura."
        case .appointment: "Escolha o paciente, o profissional e um horário disponível."
        case .patientHistory: "Consulte registros e fontes; gere um resumo somente se autorizar."
        case .examRequest: "Confira todos os exames antes de emitir e solicitar a assinatura."
        case .transcription: "Grave com autorização e revise o texto antes de utilizá-lo."
        case .financial: "Receitas, despesas e recebimentos do período permitido ao seu perfil."
        case .analytics: "Explore os indicadores disponíveis e seus limites de cobertura."
        case .interactions: "Confira princípios ativos, alertas e fontes; a decisão é profissional."
        case .medicineReference: "Busque o registro no catálogo e abra a consulta ao Bulário oficial."
        case .clarify: "Escolha uma tarefa por vez. Seu pedido permanece no rascunho."
        case .conversation: "Perguntas gerais com autorização para o processamento por IA."
        }
    }
    func isAllowed(for user: User) -> Bool {
        switch self {
        case .prescription: user.canPrescribe
        case .financial: user.canReadFinancialReports
        case .appointment: user.canConfirmAppointment
        case .patientHistory, .interactions, .transcription, .medicineReference, .conversation: user.canReadClinicalData
        case .examRequest: user.canRequestExam
        case .analytics: user.containsAnyRole(["gestor", "medico"])
        case .clarify: user.canUseLARI
        }
    }
}
