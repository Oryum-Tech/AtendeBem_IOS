import AtendeBemCore
import SwiftUI

struct HomeContextHeader: View {
    let name: String?
    let clinicName: String
    let date: Date

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = ClinicClock.timeZone
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrandLogoView().frame(width: 126, height: 28)
            Text(dateTitle).font(.subheadline).foregroundStyle(.secondary)
            Text(name ?? "Seu dia na clínica").font(.title2.weight(.semibold))
            Label(clinicName, systemImage: "building.2")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct HomeContinuationLabel: View {
    let patientName: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Retomar consulta", systemImage: "doc.badge.clock")
                .font(.subheadline.weight(.medium)).foregroundStyle(Brand.accent)
            Text(patientName).font(.headline)
            Text(status).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct HomeAppointmentFocus: View {
    let appointment: Appointment
    let patientName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let date = appointment.startDate {
                Label(ClinicClock.time(date), systemImage: "clock")
                    .font(.title2.weight(.semibold)).monospacedDigit()
            }
            Text(patientName ?? "Nome indisponível").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { details }
                VStack(alignment: .leading, spacing: 7) { details }
            }
            Text("Abrir agendamento").font(.subheadline.weight(.medium)).foregroundStyle(Brand.accent)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var details: some View {
        Text(appointment.statusLabel).font(.subheadline.weight(.medium))
        if appointment.duracaoMin > 0 {
            Text("\(appointment.duracaoMin) minutos").font(.subheadline).foregroundStyle(.secondary)
        }
        if appointment.canal == "teleconsulta" {
            Label("Teleconsulta", systemImage: "video").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct HomeLARILabel: View {
    let financialOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Peça ajuda à LARI", systemImage: "sparkles")
                .font(.headline).foregroundStyle(Brand.accent)
            Text(financialOnly ? "Consulte o financeiro por período e prepare um relatório."
                 : "Abra as tarefas e a assistência disponíveis para o seu trabalho.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Buttons remain independent inside the List row. A single destination owner in
/// TodayView prevents the old regression where every shortcut opened the same task.
struct HomeActionGrid: View {
    let actions: [ClinicalShortcut]
    @Binding var selectedAction: ClinicalShortcut?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize >= .xxxLarge ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(actions) { action in
                Button { selectedAction = action } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: action.symbol)
                            .font(.title3).foregroundStyle(Brand.accent)
                            .frame(width: 24).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(for: action)).font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(action == .lari ? "Ver tarefas e conversar" : "Escolher paciente")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title(for: action))
                .accessibilityHint(action == .lari
                    ? "Abre a assistente e as tarefas permitidas para seu perfil."
                    : "Escolha o paciente para \(action.patientPrompt).")
                .accessibilityIdentifier("home.\(action.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }

    private func title(for action: ClinicalShortcut) -> String {
        switch action {
        case .prescription: "Preparar receita"
        case .exams: "Solicitar exames"
        case .consultation: "Abrir consulta"
        case .lari: "Pedir à LARI"
        }
    }
}

struct HomeAgendaEmptyState: View {
    let hasAppointments: Bool
    let hasUnusableAppointments: Bool

    private var title: String {
        if hasUnusableAppointments { return "Próximo horário indisponível" }
        return hasAppointments ? "Sem próximo horário nesta prévia" : "Nenhum agendamento retornado"
    }

    private var detail: String {
        if hasUnusableAppointments {
            return "Alguns dados recebidos não puderam ser conferidos. Abra a agenda completa antes de concluir que não há outros horários."
        }
        return hasAppointments
            ? "Os horários retornados não incluem outro agendamento futuro ativo. Confira quem já chegou na sala de espera."
            : "A consulta de hoje não retornou horários no recorte do seu perfil. Você pode abrir a agenda completa ou conferir a sala de espera."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "calendar")
                .font(.headline)
            Text(detail)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.noUpcomingAppointment")
    }
}
