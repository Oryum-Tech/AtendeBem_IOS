import Foundation
import Testing
@testable import AtendeBemCore

private func decodeTriage(_ fields: [String: Any] = [:]) throws -> ClinicalTriage {
    var value: [String: Any] = [
        "id": "triage-fixture", "pacienteId": "patient-fixture",
        "queixaPrincipal": "Queixa fictícia registrada na triagem",
        "classificacaoRisco": "amarelo", "triadoPor": "professional-fixture",
        "triadaEm": "2026-10-02T08:10:00-03:00", "criadoEm": "2026-10-02T08:12:00-03:00",
        "sinaisVitais": []
    ]
    value.merge(fields) { _, new in new }
    return try JSONDecoder().decode(ClinicalTriage.self, from: JSONSerialization.data(withJSONObject: value))
}

@Test func triagePreservesProfessionalEncounterAndMeasurementProvenance() throws {
    let triage = try decodeTriage([
        "atendimentoId": "encounter-fixture", "observacoes": "Observação fictícia",
        "imc": 24.8,
        "sinaisVitais": [["id": "vital-fixture", "pacienteId": "patient-fixture",
            "tipo": "temperatura", "valor": 36.7, "unidade": "°C",
            "medidoEm": "2026-10-02T08:10:00-03:00"]]
    ])
    let values = try validatedTriages([triage], patientID: "patient-fixture")
    #expect(values[0].triadoPor == "professional-fixture")
    #expect(values[0].atendimentoId == "encounter-fixture")
    #expect(values[0].observacoes == "Observação fictícia")
    #expect(values[0].imc == 24.8)
    #expect(values[0].triadaEm != values[0].criadoEm)
    #expect(values[0].sinaisVitais[0].valor == 36.7)
    #expect(values[0].sinaisVitais[0].unidade == "°C")
    #expect(values[0].sinaisVitais[0].medidoEm == values[0].triadaEm)
}

@Test func triageMissingFieldsDoNotBecomeNormalFindingsOrSynthesizedMeasurements() throws {
    let triage = try decodeTriage()
    #expect(triage.imc == nil)
    #expect(triage.observacoes == nil)
    #expect(triage.atendimentoId == nil)
    #expect(triage.sinaisVitais.isEmpty)
    #expect(triage.recordedRiskLabel == "Amarelo")
    #expect(try validatedTriages([], patientID: "patient-fixture").isEmpty)
}

@Test func triageRejectsAnotherPatientEvenWhenNestedMeasurementsAreEmpty() throws {
    let triage = try decodeTriage(["pacienteId": "other-patient-fixture"])
    #expect(throws: APIError.invalidResponse) {
        try validatedTriages([triage], patientID: "patient-fixture")
    }
}

@Test func triageRejectsNestedMeasurementFromAnotherPatient() throws {
    let triage = try decodeTriage([
        "sinaisVitais": [["id": "vital-fixture", "pacienteId": "other-patient-fixture",
            "tipo": "peso", "valor": 70, "medidoEm": "2026-10-02T08:10:00-03:00"]]
    ])
    #expect(throws: APIError.invalidResponse) {
        try validatedTriages([triage], patientID: "patient-fixture")
    }
}

@Test func triageRetainsUnknownRiskAndMissingMeasurementUnit() throws {
    let triage = try decodeTriage([
        "classificacaoRisco": "protocolo_futuro",
        "sinaisVitais": [["id": "vital-fixture", "pacienteId": "patient-fixture",
            "tipo": "medida_futura", "valor": 7, "medidoEm": "2026-10-02T08:10:00-03:00"]]
    ])
    #expect(triage.recordedRiskLabel == "protocolo_futuro")
    #expect(triage.sinaisVitais[0].title == "medida_futura")
    #expect(triage.sinaisVitais[0].unidade == nil)
    #expect(try decodeTriage(["classificacaoRisco": " "]).recordedRiskLabel == "Não informada")
}
