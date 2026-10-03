import AtendeBemCore
import SwiftUI

struct FormField<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            content
        }.padding(.vertical, 4)
    }
}

struct ConnectionState: View {
    let updatedAt: Date?
    let error: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                Label(error, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("connection.error")
            }
            if isLoading { ProgressView("Atualizando…") }
            if let updatedAt {
                Text("Última atualização: \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct RetryState: View {
    let title: String
    let detail: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: { Text(detail) } actions: {
            Button("Tentar novamente", action: retry).buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

struct RestrictedState: View {
    var body: some View {
        ContentUnavailableView("Acesso restrito", systemImage: "lock",
                               description: Text("Seu perfil nesta clínica não permite acessar esta área."))
    }
}

struct PatientNameRow: View {
    let patient: Patient
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(patient.nome).font(.headline)
            if let cpf = patient.cpfMascarado { Text(cpf).font(.subheadline).foregroundStyle(.secondary) }
            if patient.rascunho == true {
                Label("Cadastro em aberto", systemImage: "pencil.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct AgendaAppointmentRow: View {
    let appointment: Appointment
    let patientName: String?
    var typeColor: Color? = nil
    var typeLabel: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(typeColor ?? appointmentAgendaColor(appointment))
                .frame(width: 4)
                .opacity(appointment.status == "completed" ? 0.55 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(agendaTimeRange(for: appointment)).font(.subheadline).monospacedDigit()
                Spacer()
                Text(appointment.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
            Text(patientName ?? "Paciente")
                .font(.headline)
                .foregroundStyle(.primary)
                .strikethrough(appointment.status == "completed")
            Label(typeLabel ?? appointmentTypeLabel(appointment), systemImage: appointment.canal == "teleconsulta" ? "video" : "circle.fill")
                .font(.caption)
                .foregroundStyle(typeColor ?? appointmentAgendaColor(appointment))
            if let confirmation = AppointmentConfirmationState.resolve(appointment) {
                Label(confirmation.label, systemImage: "checkmark.bubble").font(.caption).foregroundStyle(.secondary)
            }
            if let motivo = appointment.motivo, !motivo.isEmpty {
                Text(motivo).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let expanded: String
        if clean.count == 3 {
            expanded = clean.map { "\($0)\($0)" }.joined()
        } else {
            expanded = clean
        }
        guard expanded.count == 6, let value = UInt64(expanded, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

func appointmentAgendaColor(_ appointment: Appointment) -> Color {
    if ["cancelled", "no-show"].contains(appointment.status) { return .red }
    if appointment.status == "completed" { return .secondary }
    if appointment.canal == "teleconsulta" || appointment.tipo == "telemedicina" { return Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255) }
    switch appointment.tipo {
    case "retorno", "exame": return Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
    case "urgencia": return Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    case "procedimento": return Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
    default: return Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    }
}

private func appointmentTypeLabel(_ appointment: Appointment) -> String {
    if appointment.canal == "teleconsulta" || appointment.tipo == "telemedicina" { return "Telemedicina" }
    return ["consulta": "Consulta", "retorno": "Retorno", "urgencia": "Urgência", "exame": "Exame", "procedimento": "Procedimento"][appointment.tipo] ?? appointment.tipo.capitalized
}

fileprivate func agendaTimeRange(for appointment: Appointment) -> String {
    guard let start = appointment.startDate else { return "—" }
    let end = start.addingTimeInterval(TimeInterval(appointment.duracaoMin * 60))
    return "\(ClinicClock.time(start))–\(ClinicClock.time(end))"
}

extension View {
    @ViewBuilder func clinicalCodeInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
    @ViewBuilder func emailInput() -> some View {
        #if os(iOS)
        self.keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            .textContentType(.username)
        #else
        self.textContentType(.username).autocorrectionDisabled()
        #endif
    }

    @ViewBuilder func otpInput() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad).textContentType(.oneTimeCode)
        #else
        self.textContentType(.oneTimeCode)
        #endif
    }

    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
