import AtendeBemCore
import Foundation

/// A projection of retained task evidence. Reading progress never starts or repeats an operation.
struct LARITaskProgress: Equatable {
    let title: String
    let detail: String
    let symbol: String
    let needsAttention: Bool
    let isWorking: Bool

    init(_ title: String, _ detail: String, symbol: String, needsAttention: Bool = false, isWorking: Bool = false) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.needsAttention = needsAttention
        self.isWorking = isWorking
    }

    static let preparing = Self("Retomar preparação", "Os dados desta tarefa permanecem nesta sessão. Abra para revisar e continuar.", symbol: "pencil.circle", needsAttention: true)
    static let working = Self("Em andamento", "Aguarde a consulta ao sistema. A operação não será repetida ao abrir a tarefa.", symbol: "clock", isWorking: true)
    static let creationUncertain = Self("Conferir resultado", "O sistema pode ter recebido o pedido. Abra para conferir antes de qualquer nova tentativa.", symbol: "exclamationmark.circle", needsAttention: true)
    static let signatureUncertain = Self("Conferir assinatura", "A solicitação de assinatura ainda não foi confirmada. Abra o documento para atualizar a situação.", symbol: "signature", needsAttention: true)
    static let refreshRequired = Self("Atualizar situação", "Não foi possível confirmar a situação atual. Abra a tarefa para conferir os dados e a mensagem do sistema.", symbol: "arrow.clockwise.circle", needsAttention: true)

    private static func hasCancellation(_ statuses: String?...) -> Bool {
        statuses.compactMap { $0 }.contains {
            ["cancelado", "cancelada", "cancelled", "canceled"].contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }
    private static func cancelledDocument(isWorking: Bool, uncertain: Bool = false) -> Self {
        Self("Documento cancelado", "Uma das leituras informou cancelamento. Abra para conferir; nenhum envio anterior é revertido por este status."
             + (uncertain ? " Há uma operação sem confirmação. Não repita o pedido." : ""),
             symbol: "xmark.circle", needsAttention: true, isWorking: isWorking)
    }

    @MainActor static func prescription(_ task: LARIPrescriptionTask) -> Self {
        if hasCancellation(task.document?.status, task.signatureReview?.document?.status) {
            return cancelledDocument(isWorking: task.isWorking, uncertain: task.outcome == .uncertain || task.signatureReview?.outcome == .uncertain)
        }
        if task.isWorking { return .working }
        if task.outcome == .uncertain { return .creationUncertain }
        if task.signatureReview?.outcome == .uncertain { return .signatureUncertain }
        if task.error != nil || task.signatureReview?.error != nil { return .refreshRequired }
        if let document = task.signatureReview?.document ?? task.document {
            if document.signature != nil {
                return Self("Assinatura informada", "O serviço confirmou a assinatura. O recebimento pelo paciente não está confirmado aqui.", symbol: "signature")
            }
            if document.status == "rascunho", document.reportedSigned != true {
                return Self("Aguardando assinatura", "O rascunho foi salvo. Abra para revisar o documento e os contatos antes de assinar.", symbol: "signature", needsAttention: true)
            }
            return .refreshRequired
        }
        return task.outcome == .succeeded ? .refreshRequired : .preparing
    }

    @MainActor static func appointment(_ task: LARIAppointmentTask) -> Self {
        if hasCancellation(task.appointment?.status) {
            return Self("Agendamento cancelado", "O sistema informou cancelamento deste agendamento. Abra a tarefa para conferir os dados retornados.", symbol: "calendar.badge.exclamationmark", needsAttention: true, isWorking: task.isWorking)
        }
        if task.isWorking { return .working }
        if task.outcome == .uncertain { return .creationUncertain }
        if task.error != nil || task.lookup.error != nil { return .refreshRequired }
        if task.outcome == .succeeded, task.appointment != nil {
            return Self("Agendamento registrado", "O sistema confirmou este agendamento. Abra a tarefa para conferir os dados retornados.", symbol: "calendar.badge.checkmark")
        }
        return task.outcome == .succeeded ? .refreshRequired : .preparing
    }

    @MainActor static func exam(_ task: LARIExamRequestTask) -> Self {
        if hasCancellation(task.document?.status, task.signatureReview?.document?.status) {
            return cancelledDocument(isWorking: task.isWorking, uncertain: task.outcome == .uncertain || task.deliveryOutcome == .uncertain || task.signatureReview?.outcome == .uncertain)
        }
        if task.isWorking { return .working }
        if task.outcome == .uncertain { return .creationUncertain }
        if task.deliveryOutcome == .uncertain {
            return Self("Conferir envio", "O pedido de envio pode ter sido recebido. Não há confirmação de entrega; abra para conferir sem repetir o envio.", symbol: "exclamationmark.circle", needsAttention: true)
        }
        if task.signatureReview?.outcome == .uncertain { return .signatureUncertain }
        if task.error != nil || task.lookup.error != nil || task.deliveryError != nil || task.signatureReview?.error != nil { return .refreshRequired }
        if task.deliveryOutcome == .succeeded {
            return Self("Envio solicitado", "O serviço confirmou o enfileiramento. Isso não comprova recebimento pelo paciente.", symbol: "paperplane")
        }
        if let document = task.document {
            let signature = task.signatureReview?.document?.signature ?? document.assinatura
            if signature?.padrao == "ICP-Brasil" {
                return Self("Revisar envio", "Assinatura ICP-Brasil informada. Abra para atualizar o documento, conferir contatos e escolher os canais.", symbol: "paperplane", needsAttention: true)
            }
            return Self("Conferir assinatura", "A solicitação foi registrada. Abra o documento para conferir ou concluir a assinatura antes do envio.", symbol: "signature", needsAttention: true)
        }
        return task.outcome == .succeeded ? .refreshRequired : .preparing
    }

    @MainActor static func history(_ task: LARIHistoryTask) -> Self {
        if task.isWorking { return .working }
        if task.error != nil || task.lookup.error != nil { return .refreshRequired }
        guard task.updatedAt != nil else { return .preparing }
        guard task.timeline != nil || task.antecedents != nil || task.allergies != nil else {
            return Self("Fontes indisponíveis", "Nenhuma das fontes do histórico pôde ser consultada. Abra para conferir os avisos e tentar atualizar.", symbol: "exclamationmark.circle", needsAttention: true)
        }
        if !task.sourceWarnings.isEmpty || task.timeline?.avisos.isEmpty == false {
            return Self("Histórico parcial", "Uma ou mais fontes não estão completas. Abra para conferir os registros disponíveis e os avisos.", symbol: "exclamationmark.circle", needsAttention: true)
        }
        return Self("Histórico consultado", "Os registros desta consulta estão disponíveis na sessão. Abra para conferir a data da leitura e atualizar quando necessário.", symbol: "clock.arrow.circlepath")
    }

    @MainActor static func audio(_ session: LARIAudioTaskSession) -> Self {
        if session.cleanupError != nil {
            return Self("Conferir exclusão do áudio", "A exclusão do áudio temporário ainda não foi confirmada. Abra a tarefa para tentar novamente.", symbol: "exclamationmark.circle", needsAttention: true, isWorking: session.isWorking)
        }
        if session.isWorking {
            switch session.phase {
            case .recording: return Self("Gravação em andamento", "Abra a tarefa para acompanhar ou encerrar a gravação.", symbol: "waveform", isWorking: true)
            case .transcribing: return Self("Transcrevendo consulta", "Aguarde o processamento. Nenhuma anotação foi salva no prontuário nesta etapa.", symbol: "waveform", isWorking: true)
            default: return .working
            }
        }
        if session.error != nil { return .refreshRequired }
        switch session.phase {
        case .audioReady:
            return Self("Áudio pronto para transcrever", "Abra para conferir as autorizações e iniciar a transcrição.", symbol: "waveform", needsAttention: true)
        case .review:
            return Self("Revisar transcrição", "O texto foi retornado para revisão. Este status não confirma salvamento no prontuário.", symbol: "text.badge.checkmark", needsAttention: true)
        case .expired:
            return Self("Sessão encerrada", "Esta tarefa não está mais disponível no contexto atual.", symbol: "lock")
        default: return .preparing
        }
    }
}
