import Foundation
import Testing
@testable import AtendeBemCore

@Test func lariRoutesUserRequestsToKnownTasksWithoutInterpretingArguments() {
    #expect(LARITaskRoute.resolve("Emita uma receita de medicamento 100 mg para Paciente Fictício por 30 dias") == .prescription)
    #expect(LARITaskRoute.resolve("Me diga como foi o financeiro de janeiro desse ano") == .financial)
    #expect(LARITaskRoute.resolve("Relatório de FATURAMENTO de janeiro de 2026") == .financial)
    #expect(LARITaskRoute.resolve("Organize as anotações da consulta") == .conversation)
    #expect(LARITaskRoute.resolve("Faça uma receita e mostre o financeiro de janeiro") == .clarify)
}

@Test func lariTaskAccessDoesNotGrantClinicalPowersToFinancialRoles() throws {
    func user(_ roles: [String]) throws -> User {
        let data = try JSONSerialization.data(withJSONObject: ["id": "test-user", "nome": "Conta fictícia", "email": "test@example.invalid", "papeis": roles])
        return try JSONDecoder().decode(User.self, from: data)
    }
    for role in ["gestor", "admin", "contabilista"] {
        let value = try user([role])
        #expect(value.canUseLARI && value.canReadFinancialReports)
        #expect(!value.canPrescribe && !value.canReadClinicalData)
    }
    let doctor = try user(["medico"])
    #expect(doctor.canUseLARI && doctor.canPrescribe && !doctor.canReadFinancialReports)
    let reception = try user(["recepcao"])
    #expect(reception.canUseLARI && !reception.canReadFinancialReports && !reception.canPrescribe)
    #expect(LARITaskRoute.appointment.isAllowed(for: reception))
    for route in [LARITaskRoute.patientHistory, .examRequest, .prescription, .conversation, .transcription, .interactions, .analytics, .medicineReference] {
        #expect(!route.isAllowed(for: reception))
    }
}

@Test func medicineReferenceCommandsOpenReferenceInsteadOfInventingIndications() {
    for request in ["Consultar a bula de Produto Fictício", "Abra o Bulário", "Bula do Produto Fictício", "Qual a indicação do medicamento Produto Fictício?", "Para que serve o medicamento Produto Fictício?", "Medicamentos e bulas"] {
        #expect(LARITaskRoute.resolve(request) == .medicineReference)
    }
    #expect(LARITaskRoute.resolve("Para que serve isso?") == .clarify)
    #expect(LARITaskRoute.resolve("Qual a indicação?") == .clarify)
    #expect(LARITaskRoute.resolve("Qual a indicação para Produto Fictício?") == .clarify)
    #expect(LARITaskRoute.resolve("Consulte a bula e as interações entre medicamentos") == .clarify)
    #expect(LARITaskRoute.resolve("Prepare receita e mostre a bula") == .clarify)
    #expect(LARITaskRoute.resolve("Não consulte a bula") == .clarify)
    #expect(LARITaskRoute.resolve("Consultar a bula", includesConversationContext: true) == .conversation)
    #expect(LARITaskRoute.resolve("A bula foi atualizada") == .conversation)
}

@Test func copiedConversationCannotBecomeANativeTask() throws {
    let draft = try LARIContinuation.draft(question: "Que recursos existem?", reply: "Você pode preparar receita e consultar o financeiro.", preserving: "Explique melhor essa resposta.")
    #expect(LARITaskRoute.resolve(draft, includesConversationContext: true) == .conversation)
    #expect(LARITaskRoute.resolve("Preparar receita para Paciente Fictício", includesConversationContext: false) == .prescription)
}

@Test func expandedLARICommandsResolveOneTaskAndPreserveConversationBoundary() {
    #expect(LARITaskRoute.resolve("Agende consulta para Paciente Fictício amanhã às 14h") == .appointment)
    #expect(LARITaskRoute.resolve("Consulte o histórico do paciente Fictício") == .patientHistory)
    #expect(LARITaskRoute.resolve("Solicite exames de Hemograma para Paciente Fictício") == .examRequest)
    #expect(LARITaskRoute.resolve("Transcreva a consulta") == .transcription)
    #expect(LARITaskRoute.resolve("Pesquise sazonalidade dos atendimentos") == .analytics)
    #expect(LARITaskRoute.resolve("Confira interações entre medicamentos") == .interactions)
    #expect(LARITaskRoute.resolve("Agende consulta e solicite exames") == .clarify)
    #expect(LARITaskRoute.resolve("Não agende a consulta") == .clarify)
    #expect(LARITaskRoute.resolve("Agende uma consulta", includesConversationContext: true) == .conversation)
    for route in LARITaskRoute.tasks { #expect(LARITaskRoute.resolve(route.starter) == route) }
}

@Test func lariCatalogAnalyticsDoesNotBorrowAdministrativeOrReceptionAccess() throws {
    for role in ["recepcao", "admin", "contabilista", "enfermeiro"] {
        let data = try JSONSerialization.data(withJSONObject: ["id":"synthetic", "nome":"Conta", "email":"test@example.invalid", "papeis":[role]])
        let user = try JSONDecoder().decode(User.self, from: data)
        #expect(!LARITaskRoute.analytics.isAllowed(for: user))
    }
}

@Test func lariRecognizesCommonChartRequestsAndKeepsAmbiguousActionsForReview() {
    for text in ["Veja o prontuário de Paciente Fictício", "Prontuário de Paciente Fictício", "Antecedentes do Paciente Fictício"] {
        #expect(LARITaskRoute.resolve(text) == .patientHistory)
    }
    for text in ["Não prepare uma receita", "Não quero preparar receita", "Não peça exames", "Não transcreva a consulta", "Nunca quero que crie uma receita", "Não leia a bula", "Há interação entre sertralina e tramadol?", "Reagende a consulta", "Cancele o agendamento"] {
        #expect(LARITaskRoute.resolve(text) == .clarify, "Preserve the request for review: \(text)")
    }
    #expect(LARITaskRoute.resolve("Como melhorar a interação com o paciente?") == .conversation)
    #expect(LARITaskRoute.resolve("Veja o prontuário", includesConversationContext: true) == .conversation)
}

@Test func lariCatalogSearchUsesAccentsAndAliasesWithoutLeakingRestrictedTasks() throws {
    func user(_ role: String) throws -> User {
        try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: ["id":"synthetic", "nome":"Conta", "email":"test@example.invalid", "papeis":[role]]))
    }
    let doctor = try user("medico")
    #expect(LARITaskRoute.availableTasks(for: doctor, matching: "prontuário") == [.patientHistory])
    #expect(LARITaskRoute.availableTasks(for: doctor, matching: "audio") == [.transcription])
    #expect(LARITaskRoute.availableTasks(for: doctor, matching: "ANVISA") == [.medicineReference])
    #expect(LARITaskRoute.availableTasks(for: doctor, matching: "    ") == LARITaskRoute.tasks.filter { $0.isAllowed(for: doctor) })
    #expect(LARITaskRoute.availableTasks(for: try user("recepcao"), matching: "prontuario").isEmpty)
    #expect(LARITaskRoute.availableTasks(for: try user("contabilista"), matching: "receita") == [.financial])
}
