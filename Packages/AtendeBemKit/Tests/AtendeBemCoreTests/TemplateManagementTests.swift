import Foundation
import Testing
@testable import AtendeBemCore

private let editableTemplateFixture = #"{"id":"fixture-model","tipo":"protocolo","nome":"Modelo fictício","condicao":"Condição do modelo","cid10":["Z00.0"],"compartilhado":true,"medicamentos":[{"medicamento":"Medicamento fictício","posologia":"Posologia fictícia","dose":"Dose fictícia","frequencia":"Frequência fictícia","duracao":"Duração fictícia","instrucoes":"Instrução preservada","quantidade":"Quantidade fictícia","usoContinuo":true}],"exames":[{"descricao":"Exame fictício","tuss":"12345","justificativa":"Justificativa preservada"}],"orientacoes":"Orientação preservada","usos":2,"meu":true,"atualizadoEm":"2026-10-02T12:00:00Z"}"#

private func editableTemplate() throws -> ClinicalTemplate {
    try JSONDecoder().decode(ClinicalTemplate.self, from: Data(editableTemplateFixture.utf8))
}

private func patchJSON(_ patch: ClinicalTemplatePatch) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
}

@Test func templateApplicationRequiresReviewOfChangedClinicalContentButNotUsageMetadata() throws {
    let original = try editableTemplate()
    var json = try #require(JSONSerialization.jsonObject(with: Data(editableTemplateFixture.utf8)) as? [String: Any])
    func model(_ values: [String: Any]) throws -> ClinicalTemplate {
        try JSONDecoder().decode(ClinicalTemplate.self, from: JSONSerialization.data(withJSONObject: values))
    }
    json["usos"] = 3; json["atualizadoEm"] = "2026-10-02T15:00:00Z"
    #expect(original.hasSameContent(as: try model(json)))
    var medicines = try #require(json["medicamentos"] as? [[String: Any]])
    medicines[0]["dose"] = "Dose alterada fictícia"; json["medicamentos"] = medicines
    #expect(!original.hasSameContent(as: try model(json)))
    json = try #require(JSONSerialization.jsonObject(with: Data(editableTemplateFixture.utf8)) as? [String: Any])
    var exams = try #require(json["exames"] as? [[String: Any]])
    exams[0]["justificativa"] = "Justificativa alterada fictícia"; json["exames"] = exams
    #expect(!original.hasSameContent(as: try model(json)))
}

@Test func templateRenamingNeverRewritesUneditedClinicalContentOrSharing() throws {
    let model = try editableTemplate()
    var draft = ClinicalTemplateDraft(model)
    #expect(draft.validationError == nil)
    #expect(!ClinicalTemplatePatch(original: model, draft: draft).hasChanges)
    draft.name = "  Novo nome  "
    let patch = ClinicalTemplatePatch(original: model, draft: draft)
    let json = try patchJSON(patch)
    #expect(patch.hasChanges)
    #expect(Set(json.keys) == ["nome"])
    #expect(json["nome"] as? String == "Novo nome")
}

@Test func templateClearedOptionalFieldsAreExplicitNullRatherThanOmitted() throws {
    let model = try editableTemplate()
    var draft = ClinicalTemplateDraft(model)
    draft.condition = ""; draft.guidance = " "
    let json = try patchJSON(ClinicalTemplatePatch(original: model, draft: draft))
    #expect(json["condicao"] is NSNull)
    #expect(json["orientacoes"] is NSNull)
    #expect(json["medicamentos"] == nil)
    #expect(json["exames"] == nil)
    #expect(draft.validationError == nil) // Mixed protocol retains both types of items.
}

@Test func editingMedicinePreservesStructuredFieldsAndMixedProtocolExams() throws {
    let model = try editableTemplate()
    var draft = ClinicalTemplateDraft(model)
    draft.medicines[0].name = "Outro medicamento fictício"
    let json = try patchJSON(ClinicalTemplatePatch(original: model, draft: draft))
    let items = try #require(json["medicamentos"] as? [[String: Any]])
    #expect(items[0]["instrucoes"] as? String == "Instrução preservada")
    #expect(items[0]["dose"] as? String == "Dose fictícia")
    #expect(items[0]["frequencia"] as? String == "Frequência fictícia")
    #expect(items[0]["duracao"] as? String == "Duração fictícia")
    #expect(items[0]["quantidade"] as? String == "Quantidade fictícia")
    #expect(items[0]["usoContinuo"] as? Bool == true)
    #expect(json["exames"] == nil)
    #expect(json["cid10"] == nil)
    #expect(json["tipo"] == nil)
    #expect(json["compartilhado"] == nil)
}

@Test func editingExamPreservesTUSSAndJustification() throws {
    let model = try editableTemplate()
    var draft = ClinicalTemplateDraft(model)
    draft.exams[0].description = "Outro exame fictício"
    let json = try patchJSON(ClinicalTemplatePatch(original: model, draft: draft))
    let items = try #require(json["exames"] as? [[String: Any]])
    #expect(items[0]["tuss"] as? String == "12345")
    #expect(items[0]["justificativa"] as? String == "Justificativa preservada")
    #expect(json["medicamentos"] == nil)
}

@Test func templateEditorRejectsInvalidCodesEmptyProtocolAndOversizedItems() throws {
    var draft = ClinicalTemplateDraft(try editableTemplate())
    draft.codes = "z00.0, m54.5"
    #expect(draft.normalizedCodes == ["Z00.0", "M54.5"])
    #expect(draft.validationError == nil)
    draft.codes = "código inválido"
    #expect(draft.validationError != nil)
    draft.codes = ""; draft.exams = []; draft.medicines = []; draft.guidance = ""
    #expect(draft.validationError != nil)
    draft = ClinicalTemplateDraft(try editableTemplate())
    draft.medicines[0].dosage = String(repeating: "x", count: 401)
    #expect(draft.validationError != nil)
}

@Test func editingOptionalMedicineTextDoesNotInventAContinuousUseFlag() throws {
    // Build a model without the optional flag using JSON so null/absent semantics are explicit.
    var json = try #require(JSONSerialization.jsonObject(with: Data(editableTemplateFixture.utf8)) as? [String: Any])
    var medicines = try #require(json["medicamentos"] as? [[String: Any]])
    medicines[0].removeValue(forKey: "usoContinuo"); json["medicamentos"] = medicines
    let model = try JSONDecoder().decode(ClinicalTemplate.self, from: JSONSerialization.data(withJSONObject: json))
    var draft = ClinicalTemplateDraft(model)
    draft.medicines[0].instructions = "Nova instrução fictícia"
    let body = try patchJSON(ClinicalTemplatePatch(original: model, draft: draft))
    let items = try #require(body["medicamentos"] as? [[String: Any]])
    #expect(items[0]["usoContinuo"] == nil)
}

@Test func templateEditPreservesCatalogPresentationAndRegulatoryMetadata() throws {
    let item = PrescriptionItem(medicamento: "Produto fictício", posologia: "Instruções fictícias", concentracao: "100 mg", formaFarmaceutica: "Forma fictícia", categoriaRegulatoria: "Categoria fictícia")
    var draft = TemplateMedicineDraft(item)
    draft.dosage = "Instruções revisadas"
    let result = draft.item
    #expect(result.concentracao == item.concentracao)
    #expect(result.formaFarmaceutica == item.formaFarmaceutica)
    #expect(result.categoriaRegulatoria == item.categoriaRegulatoria)
    #expect(result.posologia == "Instruções revisadas")
}
