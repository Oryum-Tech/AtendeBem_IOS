import AtendeBemCore
import SwiftUI

/// Marketing follows the public catalog, just like the registration form.
struct RegistrationOfferLabel: View {
    @Environment(AppState.self) private var app
    @State private var offer: RegistrationPlan?

    var body: some View {
        Text(offer.map { "\($0.trialDias) dias grátis, sem cartão de crédito." }
             ?? "Conheça os recursos e as condições de cadastro.")
            .task {
                do {
                    let plans = try await app.registration.plans()
                    guard !Task.isCancelled else { return }
                    offer = plans.first { $0.trialDias >= 14 && $0.semCartao }
                } catch { offer = nil }
            }
    }
}
