import AtendeBemCore
import Foundation
import Observation

struct LARITaskRequest: Identifiable {
    let id = UUID()
    let context: UUID
    let route: LARITaskRoute
    let command: String
    var title: String { route.title }
    var symbol: String { route.symbol }
}

/// In-memory ownership survives leaving the chat. Clinic/session boundaries erase every retained task.
@Observable @MainActor final class LARITaskSessionStore {
    var requests: [LARITaskRequest] = []
    var prescriptionTasks: [UUID: LARIPrescriptionTask] = [:]
    var appointmentTasks: [UUID: LARIAppointmentTask] = [:]
    var historyTasks: [UUID: LARIHistoryTask] = [:]
    var examTasks: [UUID: LARIExamRequestTask] = [:]
    var audioSessions: [UUID: LARIAudioTaskSession] = [:]

    func request(command: String, route: LARITaskRoute, context: UUID) -> LARITaskRequest {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = requests.last(where: { $0.context == context && $0.route == route && $0.command == normalized }) { return existing }
        let request = LARITaskRequest(context: context, route: route, command: normalized)
        requests.append(request); return request
    }
    func canStartAnother(after request: LARITaskRequest) -> Bool {
        guard requests.contains(where: { $0.id == request.id }), !isWorking(request) else { return false }
        switch request.route {
        case .appointment: return appointmentTasks[request.id]?.outcome == .succeeded
        case .prescription:
            guard let task = prescriptionTasks[request.id] else { return false }
            return task.outcome == .succeeded && task.signatureReview?.outcome != .uncertain
        case .examRequest:
            guard let task = examTasks[request.id] else { return false }
            return task.outcome == .succeeded && task.deliveryOutcome != .uncertain && task.signatureReview?.outcome != .uncertain
        default: return false
        }
    }
    /// An explicit gesture opens a new review form; it never repeats the preceding server operation.
    func startAnother(after previous: LARITaskRequest) -> LARITaskRequest? {
        guard canStartAnother(after: previous) else { return nil }
        let request = LARITaskRequest(context: previous.context, route: previous.route, command: previous.command)
        requests.append(request); return request
    }
    func isWorking(_ request: LARITaskRequest) -> Bool {
        prescriptionTasks[request.id]?.isWorking == true || appointmentTasks[request.id]?.isWorking == true ||
        historyTasks[request.id]?.isWorking == true || examTasks[request.id]?.isWorking == true || audioSessions[request.id]?.isWorking == true
    }
    func progress(for request: LARITaskRequest) -> LARITaskProgress {
        guard requests.contains(where: { $0.id == request.id }) else {
            return LARITaskProgress("Sessão encerrada", "Esta tarefa não está mais disponível na sessão atual.", symbol: "lock")
        }
        switch request.route {
        case .prescription: return prescriptionTasks[request.id].map(LARITaskProgress.prescription) ?? .preparing
        case .appointment: return appointmentTasks[request.id].map(LARITaskProgress.appointment) ?? .preparing
        case .examRequest: return examTasks[request.id].map(LARITaskProgress.exam) ?? .preparing
        case .patientHistory: return historyTasks[request.id].map(LARITaskProgress.history) ?? .preparing
        case .transcription: return audioSessions[request.id].map(LARITaskProgress.audio) ?? .preparing
        case .financial, .analytics, .interactions, .medicineReference:
            return LARITaskProgress("Abrir consulta", "Abra para escolher os dados e consultar a fonte. O resultado desta consulta não fica retido no painel.", symbol: request.symbol)
        case .clarify, .conversation:
            return LARITaskProgress("Revisar pedido", "Confira o pedido antes de continuar.", symbol: request.symbol, needsAttention: true)
        }
    }
    func discardAudioSessions() {
        for session in audioSessions.values { session.invalidate() }
        audioSessions = [:]; requests.removeAll { $0.route == .transcription }
    }
    func invalidateAll() {
        for task in prescriptionTasks.values { task.invalidate() }
        for task in appointmentTasks.values { task.invalidate() }
        for task in historyTasks.values { task.invalidate() }
        for task in examTasks.values { task.invalidate() }
        discardAudioSessions()
        prescriptionTasks = [:]; appointmentTasks = [:]; historyTasks = [:]; examTasks = [:]; requests = []
    }
}
