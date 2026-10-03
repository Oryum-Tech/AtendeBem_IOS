import Foundation
import Testing
@testable import AtendeBemCore

private func chartDecode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

@Test func patientChartKeepsClinicalAndAdministrativeFieldsWithoutInventingMissingData() throws {
    let patient = try chartDecode(Patient.self, #"{"id":"fixture","nome":"Paciente fictício","sexo":"F","endereco":{"logradouro":"Rua fictícia","numero":"10","cidade":"Cidade fictícia","uf":"RS"},"convenio":{"operadora":"Operadora fictícia","carteirinha":"carteira-ficticia","validade":"2027-01-01"},"contatoEmergencia":{"nome":"Contato fictício","parentesco":"familiar","celular":"telefone-ficticio"},"tipoSanguineo":"A+","tags":["Marcador fictício"],"observacao":"Observação fictícia","alergias":[{"id":"allergy-fixture","substancia":"Substância fictícia","tipo":"intolerancia","severidade":"leve","anafilaxia":false,"fonte":"Relato fictício","criadoEm":"2026-10-02T12:00:00Z"}]}"#)
    #expect(patient.contatoEmergencia?.nome == "Contato fictício")
    #expect(patient.endereco?.numero == "10")
    #expect(patient.convenio?.validade == "2027-01-01")
    #expect(patient.tipoSanguineo == "A+")
    #expect(patient.tags == ["Marcador fictício"])
    #expect(patient.alergias?.first?.fonte == "Relato fictício")
    #expect(patient.alergias?.first?.anafilaxia == false)
    #expect(patient.alergias?.first?.reacao == nil)
    let administrative = try chartDecode(Patient.self, #"{"id":"fixture","nome":"Paciente fictício","contatoEmergencia":{"nome":"Contato fictício"}}"#)
    #expect(administrative.contatoEmergencia != nil)
    #expect(administrative.tipoSanguineo == nil)
    #expect(administrative.alergias == nil)
    #expect(administrative.condicoes == nil)
    #expect(administrative.tags == nil)
}

@Test func evolutionPreservesLateEntryMetadataAndSnapshotSectionOrder() throws {
    let evolution = try chartDecode(Evolution.self, #"{"id":"e-fixture","pacienteId":"fixture","profissionalId":"professional-fixture","data":"2026-09-30T09:00:00-03:00","criadoEm":"2026-10-02T10:00:00-03:00","escritaDiasDepois":2,"tipo":"adendo","soap":{"s":"Subjetivo preservado","hda":"História preservada","p":"Plano preservado","legado":"Texto legado preservado"},"secoes":[{"id":"hda","sigla":"HDA","titulo":"História atual"},{"id":"p","sigla":"C","titulo":"Conduta registrada"},{"id":"s","sigla":"S","titulo":"Relato do paciente"}],"queixaPrincipal":"Queixa fictícia","cid10":["Z00.0"],"assinado":false,"rascunhoAutomatico":true,"rascunhoVersao":4,"rascunhoSalvoEm":"2026-10-02T10:01:00-03:00"}"#)
    #expect(evolution.escritaDiasDepois == 2)
    #expect(evolution.criadoEm != evolution.data)
    #expect(evolution.queixaPrincipal == "Queixa fictícia")
    #expect(evolution.displaySections.map(\.id) == ["hda", "p", "s", "legado"])
    #expect(evolution.displaySections[1].title == "C — Conduta registrada")
    #expect(evolution.displaySections[1].text == "Plano preservado")
    #expect(evolution.displaySections.last?.text == "Texto legado preservado")
    #expect(evolution.rascunhoSalvoEm != nil)
}

@Test func legacyEvolutionDoesNotPretendToKnowWhenNoteWasWritten() throws {
    let evolution = try chartDecode(Evolution.self, #"{"id":"e-fixture","pacienteId":"fixture","profissionalId":"professional-fixture","data":"2026-10-02T09:00:00-03:00","tipo":"evolucao","soap":{"s":"Texto fictício"},"cid10":[],"assinado":false}"#)
    #expect(evolution.criadoEm == nil)
    #expect(evolution.escritaDiasDepois == nil)
    #expect(evolution.rascunhoSalvoEm == nil)
    #expect(evolution.displaySections.map(\.title) == ["S — Subjetivo"])
}

@Test func chartRejectsRecordsFromAnotherPatientAndPreservesProblemNumber() throws {
    let problems = try chartDecode([ClinicalProblem].self, #"[{"id":"problem-fixture","pacienteId":"fixture","numero":17,"descricao":"Problema fictício","status":"resolvido","criadoEm":"2026-10-02T09:00:00-03:00"}]"#)
    #expect(try validatedChartEntries(problems, patientID: "fixture").first?.numero == 17)
    #expect(problems.first?.inicioEm == nil)
    #expect(throws: APIError.invalidResponse) { try validatedChartEntries(problems, patientID: "other-fixture") }
}

@Test func chartVitalDoesNotInventUnitsOrMergeDifferentMeasurementTimes() throws {
    let values = try chartDecode([ClinicalVital].self, #"[{"id":"v1","pacienteId":"fixture","tipo":"pa_sistolica","valor":120,"medidoEm":"2026-10-02T09:00:00-03:00"},{"id":"v2","pacienteId":"fixture","tipo":"pa_diastolica","valor":80,"unidade":"mmHg","medidoEm":"2026-10-01T09:00:00-03:00"}]"#)
    #expect(values[0].unidade == nil)
    #expect(values[1].unidade == "mmHg")
    #expect(values[0].medidoEm != values[1].medidoEm)
    #expect(values[0].title == "Pressão sistólica")
}

@Test func patientMedicationReportKeepsProvenanceUnknownDoseAndCoverage() throws {
    let list = try chartDecode(ReportedMedicationList.self, #"{"medicamentos":[{"id":"reported-fixture","pacienteId":"fixture","nome":"Medicamento fictício","concentracao":null,"forma":null,"via":null,"esquema":"nao_informado","horarios":[],"unidadesPorTomada":null,"inicioEm":null,"observacao":null,"ativo":true,"suspensoEm":null,"motivoSuspensao":null,"identificacao":{"principioAtivo":null,"catalogoId":null,"entraNaChecagem":false},"procedencia":{"relatadoPor":"paciente","canal":"portal-paciente","origem":"nao_informado","receitaId":null,"prescritoPor":null},"registradoEm":"2026-10-02T09:00:00-03:00","atualizadoEm":"2026-10-02T09:00:00-03:00","vistoEm":null}],"cobertura":{"ativos":1,"comPrincipioAtivo":0,"semPrincipioAtivo":["Medicamento fictício"]}}"#)
    let item = try #require(list.medicamentos.first)
    #expect(item.procedencia.relatadoPor == "paciente")
    #expect(item.unidadesPorTomada == nil)
    #expect(!item.identificacao.entraNaChecagem)
    #expect(item.scheduleLabel == "Esquema de uso não informado")
    #expect(list.cobertura.semPrincipioAtivo == ["Medicamento fictício"])
    #expect(list.cobertura.comPrincipioAtivo == 0)
}

@Test func timelineSummaryRetainsSourceWarningAndDischargedVsOngoingStays() throws {
    let timeline = try chartDecode(ClinicalTimeline.self, #"{"pacienteId":"fixture","resumo":{"totalConsultas":4,"primeiraInteracao":null,"ultimaInteracao":null,"totalInternacoes":3,"diasInternado":5,"internacoesEmCurso":1,"diagnosticosAtivos":2},"eventos":[],"paginacao":{"page":1,"perPage":30,"total":0,"totalPaginas":0},"avisos":[{"servico":"svc-exames","tiposAusentes":["exame"],"mensagem":"Fonte indisponível"}]}"#)
    #expect(timeline.resumo?.diasInternado == 5)
    #expect(timeline.resumo?.internacoesEmCurso == 1)
    #expect(timeline.resumo?.diagnosticosAtivos == 2)
    #expect(timeline.avisos.first?.tiposAusentes == ["exame"])
}
