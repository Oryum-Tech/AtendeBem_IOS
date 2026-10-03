import Foundation
import Testing
@testable import AtendeBemCore

private func roleUser(_ roles: [String]) throws -> User {
    let data = try JSONSerialization.data(withJSONObject: ["id": "fixture-user", "nome": "Profissional fictício", "email": "fixture@example.invalid", "papeis": roles])
    return try JSONDecoder().decode(User.self, from: data)
}

@Test func receptionCanCoordinateClinicWithoutClinicalActions() throws {
    let user = try roleUser(["recepcao"])
    #expect(user.canReadAgenda)
    #expect(user.canConfirmAppointment)
    #expect(user.canReadPatients)
    #expect(user.canCreatePatient)
    #expect(user.canEditPatient)
    #expect(!user.canReadClinicalData)
    #expect(!user.canPrescribe)
    #expect(!user.canIssueDocument)
    #expect(!user.canRequestExam)
    #expect(!user.canRecordAllergy)
    #expect(!user.canWriteClinicalDraft)
    #expect(user.roleSummary == "Recepção")
}

@Test func clinicRolesAccumulateWithoutTurningManagementIntoClinicalAccess() throws {
    let management = try roleUser(["gestor"])
    #expect(management.canReadAgenda)
    #expect(!management.canConfirmAppointment)
    #expect(!management.canReadClinicalData)
    #expect(!management.canPrescribe)
    let combined = try roleUser(["medico", "gestor"])
    #expect(combined.canConfirmAppointment)
    #expect(combined.canReadClinicalData)
    #expect(combined.canPrescribe)
    #expect(combined.canSignEvolution)
    #expect(combined.roleSummary == "Medicina · Gestão")
}

@Test func platformAdminDoesNotInheritProfessionalActions() throws {
    let user = try roleUser(["admin"])
    #expect(user.canReadAgenda)
    #expect(user.canCreatePatient)
    #expect(user.canConfirmAppointment)
    #expect(user.hasAnyRole(["medico"])) // Legacy navigation helper only.
    #expect(!user.containsAnyRole(["medico"]))
    #expect(!user.canPrescribe)
    #expect(!user.canIssueDocument)
    #expect(!user.canSignEvolution)
    #expect(!user.canReadClinicalData)
    #expect(!user.canRecordAllergy)
    #expect(!user.canWriteClinicalDraft)
    #expect(try roleUser(["admin", "medico"]).canPrescribe)
}

@Test func nursingAndOtherProfessionalRolesKeepTheirSpecificCapabilities() throws {
    let nurse = try roleUser(["enfermeiro"])
    #expect(nurse.canConfirmAppointment)
    #expect(nurse.canRecordAllergy)
    #expect(nurse.canRequestExam)
    #expect(nurse.canWriteClinicalDraft)
    #expect(nurse.needsNursingRegistrationTerm)
    #expect(!nurse.canPrescribe)
    #expect(!nurse.canIssueDocument)
    #expect(!nurse.canSignEvolution)
    for role in ["fisioterapeuta", "psicologo", "fonoaudiologo", "nutricionista"] {
        let user = try roleUser([role])
        #expect(user.canReadClinicalData)
        #expect(user.canIssueDocument)
        #expect(user.canRequestExam)
        #expect(!user.canPrescribe)
    }
    #expect(try roleUser(["dentista"]).canPrescribe)
}

@Test func RolesFromOneClinicAreNotAssumedInAnotherProfile() throws {
    let firstClinic = try roleUser(["medico", "gestor"])
    let secondClinic = try roleUser(["recepcao"])
    #expect(firstClinic.canPrescribe)
    #expect(!secondClinic.canPrescribe)
    #expect(!secondClinic.canReadClinicalData)
    #expect(secondClinic.canConfirmAppointment)
    #expect(secondClinic.roleSummary == "Recepção")
}

@Test func AcademicOrUnknownRolesNeverGrantClinicalOrReceptionCapabilities() throws {
    for roles in [["residente"], ["preceptor"], ["contabilista"], ["future-role"], []] {
        let user = try roleUser(roles)
        #expect(!user.canConfirmAppointment)
        #expect(!user.canPrescribe)
        #expect(!user.canIssueDocument)
        #expect(!user.canReadClinicalData)
    }
    #expect(try roleUser([]).roleSummary == "Sem perfil atribuído nesta clínica")
    #expect(try roleUser(["recepcao", "recepcao"]).roleSummary == "Recepção")
}
