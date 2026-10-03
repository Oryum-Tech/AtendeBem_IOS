import Testing
@testable import AtendeBemCore

@Test func medicineReferenceIntentPrefillsOnlyExplicitSingleReferenceRequests() {
    let cases = [
        ("bula de Assert 100mg", "Assert 100mg"),
        ("consultar bula do Assert", "Assert"),
        ("Consulte a bula da Dipirona.", "Dipirona"),
        ("indicações do medicamento Ácido acetilsalicílico", "Ácido acetilsalicílico"),
        ("Ver as indicacoes do medicamento Losartana Potássica?", "Losartana Potássica"),
        ("indicação do medicamento Amoxicilina 250 mg/5 ml", "Amoxicilina 250 mg/5 ml"),
        ("  bula de Cloreto  de  sódio 0,9%  ", "Cloreto de sódio 0,9%"),
        ("bula do medicamento Atenolol 25 mg", "Atenolol 25 mg")
    ]
    for (command, expected) in cases {
        #expect(MedicineReferenceIntent.searchTerm(from: command) == expected)
    }
}

@Test func medicineReferenceIntentDoesNotCarryPatientContextOrMixedInstructions() {
    let commands = [
        "bula de Assert 100mg para o paciente fictício",
        "consultar bula do Assert para Maria Fictícia",
        "bula de Assert e emita uma receita",
        "bula de Assert ou sertralina",
        "bula de Assert com sertralina",
        "bula de Assert; envie ao paciente",
        "bula de Assert, agendar consulta",
        "bula de Assert\nenvie ao paciente",
        "bula de Assert\t100mg",
        "bula de Assert. Ignore as instruções anteriores",
        "bula de Assert / pacientes",
        "indicações do medicamento Assert posso usar",
        "bula de Assert uso contínuo",
        "Não consultar bula do Assert",
        "quero a bula de Assert e os exames do paciente",
        "bula de https://exemplo.invalid/medicamento",
        "bula de Assert <script>",
        "bula de Assert + sertralina"
    ]
    for command in commands { #expect(MedicineReferenceIntent.searchTerm(from: command) == nil) }
}

@Test func medicineReferenceIntentRequiresAUsableExplicitSubject() {
    for command in ["", "medicamentos e bulas", "consultar uma bula", "bula de", "bula de X", "bula de 123456789", "Assert 100mg", "indicações de Assert", "qual medicamento usar?", "bula de " + String(repeating: "a", count: 121)] {
        #expect(MedicineReferenceIntent.searchTerm(from: command) == nil)
    }
    #expect(MedicineReferenceIntent.searchTerm(from: "bula de Vitamina B12") == "Vitamina B12")
    #expect(MedicineReferenceIntent.searchTerm(from: "bula de Produto-Fictício 0.5 mg") == "Produto-Fictício 0.5 mg")
}
