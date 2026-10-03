import Foundation
import Testing
@testable import AtendeBemCore

private let clinicalTemplateJSON = #"{"id":"fixture-template","tipo":"receita","nome":"Modelo fictício","cid10":["Z00"],"compartilhado":false,"medicamentos":[{"medicamento":"Item fictício","posologia":"Instrução fictícia","dose":"dose do modelo","frequencia":"frequência do modelo","duracao":"duração do modelo","instrucoes":"orientação do item","quantidade":"quantidade do modelo","usoContinuo":true}],"exames":[],"usos":2,"meu":true,"atualizadoEm":"2026-10-02T12:00:00-03:00"}"#

@Test func applyingPrescriptionTemplatePreservesEveryStructuredInstruction() throws {
    let template = try JSONDecoder().decode(ClinicalTemplate.self, from: Data(clinicalTemplateJSON.utf8))
    #expect(template.canApply(to: .prescription))
    let body = CreatePrescription(pacienteId: "patient-fixture", profissionalId: "professional-fixture", tipo: "comum", itens: template.medicamentos, orientacoes: template.orientacoes, justificativaAlergia: nil)
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
    let items = try #require(json["itens"] as? [[String: Any]])
    #expect(items[0]["dose"] as? String == "dose do modelo")
    #expect(items[0]["frequencia"] as? String == "frequência do modelo")
    #expect(items[0]["duracao"] as? String == "duração do modelo")
    #expect(items[0]["instrucoes"] as? String == "orientação do item")
    #expect(items[0]["usoContinuo"] as? Bool == true)
    #expect(items[0]["quantidade"] as? String == "quantidade do modelo")
    #expect(json["cid10"] == nil) // Applying a model is not a diagnosis.
}

@Test func mixedProtocolCannotSilentlyBecomeOnlyAPrescription() throws {
    let json = clinicalTemplateJSON.replacingOccurrences(of: #""tipo":"receita""#, with: #""tipo":"protocolo""#)
        .replacingOccurrences(of: #""exames":[]"#, with: #""exames":[{"descricao":"Exame fictício","justificativa":"Motivo fictício"}]"#)
    let template = try JSONDecoder().decode(ClinicalTemplate.self, from: Data(json.utf8))
    #expect(!template.canApply(to: .prescription))
    #expect(!template.canApply(to: .exams))
    #expect(template.examIndication == "Exame fictício: Motivo fictício")
}

@Test func prescriptionPreferenceDistinguishesDefaultFromExplicitChoice() throws {
    let unsaved = try JSONDecoder().decode(PrescriptionPreferences.self, from: Data(#"{"tamanhoFonte":"padrao","configurado":false}"#.utf8))
    let saved = try JSONDecoder().decode(PrescriptionPreferences.self, from: Data(#"{"tamanhoFonte":"padrao","configurado":true}"#.utf8))
    #expect(unsaved.needsSave(.standard))
    #expect(!saved.needsSave(.standard))
    #expect(saved.needsSave(.large))
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(PrescriptionPreferences.self, from: Data(#"{"tamanhoFonte":"future","configurado":true}"#.utf8)) }
}

@Test func examTemplateKeepsBothGuidanceAndPerExamJustification() throws {
    let json = #"{"id":"fixture","tipo":"exames","nome":"Exames fictícios","cid10":[],"compartilhado":false,"medicamentos":[],"exames":[{"descricao":"Exame A","tuss":"123","justificativa":"Razão A"},{"descricao":"Exame B","justificativa":"Razão B"}],"orientacoes":"Orientação geral","usos":0,"meu":true,"atualizadoEm":"2026-10-02"}"#
    let template = try JSONDecoder().decode(ClinicalTemplate.self, from: Data(json.utf8))
    #expect(template.canApply(to: .exams))
    #expect(!template.canApply(to: .prescription))
    #expect(template.examIndication == "Orientação geral\nExame A: Razão A\nExame B: Razão B")
    let input = CreateExamRequest(pacienteId: "fixture-patient", pacienteNome: "Fictício", tipo: "laboratorial", itens: template.exames.map { ExamItem(tuss: $0.tuss, descricao: $0.descricao) }, indicacaoClinica: template.examIndication, medicoNome: nil, medicoCrm: nil)
    let body = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    let items = try #require(body["itens"] as? [[String: Any]])
    #expect(items.count == 2)
    #expect(items[0]["tuss"] as? String == "123")
    #expect(items[0]["justificativa"] == nil) // The target DTO only accepts description + TUSS.
    #expect(body["indicacaoClinica"] as? String == template.examIndication)
}

@Test func agendaTimelineUsesClinicTimezoneAndKeepsEarlyAndLateAppointments() throws {
    func appointment(_ instant: String) throws -> Appointment {
        try JSONDecoder().decode(Appointment.self, from: Data("""
        {"id":"fixture","pacienteId":"fixture","profissionalId":"fixture","inicio":"\(instant)","duracaoMin":30,"tipo":"consulta","canal":"presencial","status":"confirmed"}
        """.utf8))
    }
    let early = try appointment("2026-10-02T09:30:00Z")
    let late = try appointment("2026-10-03T01:00:00Z")
    #expect(AgendaPresentation.hour(of: early) == 6)
    #expect(AgendaPresentation.hour(of: late) == 22)
    #expect(AgendaPresentation.hours(for: [early, late]) == Array(6...22))
    #expect(AgendaPresentation.hours(for: []) == Array(8...18))
}
