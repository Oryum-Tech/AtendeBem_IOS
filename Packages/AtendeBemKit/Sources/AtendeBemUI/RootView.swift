import SwiftUI

public struct AtendeBemRootView: View {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            Group {
                switch app.phase {
                case .loading: ProgressView("Abrindo sua clínica…")
                case .signedOut: LoginView()
                case .ready: MainTabs().id(app.contextID)
                case .changePassword: PasswordChangeView()
                case .recoverableError(let detail):
                    VStack {
                        RetryState(title: "Não foi possível abrir sua clínica", detail: detail) {
                            Task { await app.loadContext() }
                        }
                        Button("Sair da conta", role: .destructive) { Task { await app.signOut() } }
                            .controlSize(.large).padding()
                    }
                }
            }
            .accessibilityHidden(scenePhase != .active)
            if scenePhase != .active {
                Rectangle().fill(.background).ignoresSafeArea()
                BrandLogoView().frame(width: 140, height: 40)
            }
        }
        .environment(app)
        .tint(Brand.accent)
        .task { await app.start() }
    }
}

struct MainTabs: View {
    @Environment(AppState.self) private var app
    @State private var selection = WorkspaceDestination.today
    @State private var preferences = WorkspacePreferences()

    var body: some View {
        tabs
            .adaptiveAppTabs()
            .environment(preferences)
            .preferredColorScheme(preferences.appearance.colorScheme)
            .task(id: app.contextID) {
                guard let user = app.user else { return }
                preferences.configure(user: user, clinicID: app.activeClinicID)
                if !preferences.destinations.contains(selection) { selection = preferences.destinations.first ?? .today }
            }
            .onChange(of: preferences.destinations) { _, destinations in
                if !destinations.contains(selection) { selection = destinations.first ?? .today }
            }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(preferences.destinations) { destination in
                NavigationStack { destinationView(destination) }
                    .tabItem { Label(destination.title, systemImage: destination.symbol) }
                    .tag(destination)
            }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: WorkspaceDestination) -> some View {
        switch destination {
        case .today: TodayView()
        case .agenda: AgendaView()
        case .patients: PatientsView()
        case .lari: LARIChatView()
        case .finance: FinancialDashboardView()
        case .more: MoreView()
        }
    }
}

private extension View {
    @ViewBuilder
    func adaptiveAppTabs() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}
