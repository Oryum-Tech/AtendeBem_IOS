import Foundation

/// Only fresh user-authored requests select a known native task. No model-selected HTTP paths.
public enum LARITaskRoute: String, Equatable, Sendable, CaseIterable, Identifiable {
    case prescription, financial, appointment, patientHistory, examRequest, transcription, analytics, interactions, medicineReference
    case clarify, conversation
    public var id: String { rawValue }

    public static func resolve(_ text: String, includesConversationContext: Bool = false) -> Self {
        guard !includesConversationContext else { return .conversation }
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        func has(_ pattern: String) -> Bool { normalized.range(of: pattern, options: .regularExpression) != nil }
        let prescription = has(#"\b(receita|receitas|prescricao|prescricoes|prescreva|prescrever)\b"#)
            && (has(#"\b(emitir|emita|criar|crie|preparar|prepare|fazer|faca|gerar|gere|prescreva|prescrever)\b"#)
                || normalized.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("receita de ")
                || normalized.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("receita para "))
        let appointment = has(#"\b(agende|agendar|agendamento|marque|marcar)\b"#)
            && !has(#"\b(cancelar|cancele|reagendar|reagende|desmarcar|desmarque)\b"#)
        let appointmentChange = has(#"\b(cancelar|cancele|reagendar|reagende|desmarcar|desmarque)\b"#)
            && has(#"\b(consulta|consultas|agendamento|agendamentos|horario)\b"#)
        let history = has(#"\b(historico|prontuario|antecedentes)\b"#)
            && has(#"\b(paciente|consulte|consultar|mostre|mostrar|veja|ver|resuma|resumir|(?:historico|prontuario|antecedentes) (?:de|do|da))\b"#)
        let exams = has(#"\b(exame|exames|requisicao)\b"#)
            && has(#"\b(solicite|solicitar|requisitar|requisite|pedir|peca|pedido|requisicao|emitir|emita|preparar|prepare)\b"#)
        let transcription = has(#"\b(transcreva|transcrever|transcricao|gravar|grave|ditar|ditado)\b"#)
        let analytics = has(#"\b(demografia|demografico|demografica|demograficos|demograficas|sazonalidade|sazonal|sazonais|perfil populacional)\b"#)
        let interactions = has(#"\b(interacao|interacoes)\b"#) && has(#"\b(medicamento|medicamentos|medicamentosa|medicamentosas|farmaco|farmacos|principios|principio)\b"#)
        let leaflet = has(#"\b(bula|bulas|bulario)\b"#)
            && (has(#"\b(consultar|consulte|buscar|busque|mostre|mostrar|ver|abrir|abra|ler|leia|quero|preciso|qual|onde|acessar)\b"#)
                || has(#"^\s*(bula|bulas|bulario|medicamentos e bulas)\b"#))
        let indication = has(#"\b(indicacao|indicacoes|para que serve|para o que serve)\b"#)
        let medicineSubject = has(#"\b(medicamento|medicamentos|remedio|remedios|farmaco|farmacos|principio ativo)\b"#)
        let medicineReference = leaflet || (indication && medicineSubject)
        let candidates: [(Self, Bool)] = [
            (.prescription, prescription), (.financial, has(#"\b(financeiro|financeira|faturamento|faturamos|recebimentos|despesas)\b"#)),
            (.appointment, appointment), (.patientHistory, history), (.examRequest, exams),
            (.transcription, transcription), (.analytics, analytics), (.interactions, interactions), (.medicineReference, medicineReference)
        ]
        let matches = candidates.filter { $0.1 }.map { $0.0 }
        // Rescheduling/cancellation are not implemented by the creation task.
        if appointmentChange { return .clarify }
        if matches.count > 1 { return .clarify }
        // An unspecified indication question must not be answered as a drug-specific recommendation.
        if matches.isEmpty && indication { return .clarify }
        // Drug names are not inferred from free text; require the user to choose and review.
        if matches.isEmpty && has(#"\b(interacao|interacoes)\s+entre\b"#) { return .clarify }
        // A negated imperative must never be treated as permission to prepare an operation.
        if !matches.isEmpty && has(#"\b(nao|nunca)\s+(?:quero\s+(?:que\s+)?)?(?:agende|agendar|marque|marcar|emita|emitir|solicite|solicitar|grave|gravar|envie|enviar|consulte|consultar|busque|buscar|abra|abrir|prepare|preparar|crie|criar|faca|fazer|gere|gerar|prescreva|prescrever|peca|pedir|requisite|requisitar|transcreva|transcrever|leia|ler|mostre|mostrar|veja|ver|resuma|resumir)\b"#) { return .clarify }
        return matches.first ?? .conversation
    }
}

public extension User {
    var canReadFinancialReports: Bool { containsAnyRole(["gestor", "admin", "contabilista"]) }
    var canUseLARI: Bool { canReadClinicalData || canReadFinancialReports || canConfirmAppointment }
}
