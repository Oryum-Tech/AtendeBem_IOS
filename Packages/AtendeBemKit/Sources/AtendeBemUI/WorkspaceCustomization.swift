import AtendeBemCore
import Foundation
import Observation
import SwiftUI

enum WorkspaceDestination: String, CaseIterable, Codable, Identifiable {
    case today
    case agenda
    case patients
    case lari
    case finance
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Hoje"
        case .agenda: "Agenda"
        case .patients: "Pacientes"
        case .lari: "LARI"
        case .finance: "Financeiro"
        case .more: "Mais"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .agenda: "calendar"
        case .patients: "person.2"
        case .lari: "sparkles"
        case .finance: "chart.line.uptrend.xyaxis"
        case .more: "ellipsis.circle"
        }
    }

    func isAllowed(for user: User) -> Bool {
        switch self {
        case .today, .more: true
        case .agenda: user.canReadAgenda
        case .patients: user.canReadPatients
        case .lari: user.canUseLARI
        case .finance: user.canReadFinancialReports
        }
    }
}

enum HomeWidget: String, CaseIterable, Codable, Identifiable {
    case waitingQueue
    case todayAgenda
    case clinicalShortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waitingQueue: "Fila de espera"
        case .todayAgenda: "Agenda de hoje"
        case .clinicalShortcuts: "Ações frequentes"
        }
    }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "Acompanhar o sistema"; case .light: "Claro"; case .dark: "Escuro" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

@MainActor @Observable
final class WorkspacePreferences {
    private(set) var destinations: [WorkspaceDestination] = [.today, .agenda, .patients, .more]
    private(set) var quickActions = ClinicalShortcut.allCases
    private(set) var homeWidgets: [HomeWidget] = HomeWidget.allCases
    private(set) var appearance = AppAppearance.system
    private var storageKey: String?

    func configure(user: User, clinicID: String?) {
        let key = "atendebem.workspace.\(user.id).\(clinicID ?? "default")"
        guard storageKey != key else {
            // Roles can change while the same clinic and account stay selected.
            destinations = normalized(destinations, for: user)
            quickActions = quickActions.filter { $0.isAllowed(for: user) }
            save()
            return
        }
        storageKey = key

        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(SavedWorkspace.self, from: data) {
            appearance = saved.appearance ?? .system
            destinations = normalized(saved.destinations, for: user)
            homeWidgets = saved.homeWidgets.filter(HomeWidget.allCases.contains)
            var seen: Set<ClinicalShortcut> = []
            quickActions = (saved.quickActions ?? ClinicalShortcut.allCases).filter { seen.insert($0).inserted && $0.isAllowed(for: user) }
        } else {
            appearance = .system
            destinations = normalized([.today, .agenda, .patients, .more], for: user)
            homeWidgets = HomeWidget.allCases
            quickActions = ClinicalShortcut.allCases.filter { $0.isAllowed(for: user) }
        }
    }

    func setAppearance(_ value: AppAppearance) { appearance = value; save() }

    func setDestination(_ destination: WorkspaceDestination, enabled: Bool, user: User) {
        guard destination != .more, destination.isAllowed(for: user) else { return }
        if enabled {
            guard !destinations.contains(destination), destinations.count < 4 else { return }
            destinations.insert(destination, at: max(0, destinations.count - 1))
        } else {
            destinations.removeAll { $0 == destination }
        }
        destinations = normalized(destinations, for: user)
        save()
    }

    func moveDestinations(from offsets: IndexSet, to destination: Int, user: User) {
        var editable = destinations.filter { $0 != .more }
        let translatedOffsets = IndexSet(offsets.filter { $0 < editable.count })
        guard !translatedOffsets.isEmpty else { return }
        editable.move(fromOffsets: translatedOffsets, toOffset: min(destination, editable.count))
        destinations = normalized(editable + [.more], for: user)
        save()
    }

    func setHomeWidget(_ widget: HomeWidget, enabled: Bool) {
        if enabled, !homeWidgets.contains(widget) { homeWidgets.append(widget) }
        if !enabled { homeWidgets.removeAll { $0 == widget } }
        save()
    }

    func setQuickAction(_ action: ClinicalShortcut, enabled: Bool) {
        if enabled, !quickActions.contains(action) { quickActions.append(action) }
        if !enabled { quickActions.removeAll { $0 == action } }
        save()
    }

    func moveQuickActions(from offsets: IndexSet, to destination: Int) {
        quickActions.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func reset(for user: User) {
        destinations = normalized([.today, .agenda, .patients, .more], for: user)
        homeWidgets = HomeWidget.allCases
        quickActions = ClinicalShortcut.allCases.filter { $0.isAllowed(for: user) }
        appearance = .system
        save()
    }

    private func normalized(_ values: [WorkspaceDestination], for user: User) -> [WorkspaceDestination] {
        WorkspacePolicy.tabs(values.map(\.rawValue), user: user).compactMap(WorkspaceDestination.init(rawValue:))
    }

    private func save() {
        guard let storageKey,
              let data = try? JSONEncoder().encode(SavedWorkspace(destinations: destinations, homeWidgets: homeWidgets, quickActions: quickActions, appearance: appearance)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct SavedWorkspace: Codable {
    let destinations: [WorkspaceDestination]
    let homeWidgets: [HomeWidget]
    let quickActions: [ClinicalShortcut]?
    let appearance: AppAppearance?
}

struct WorkspaceCustomizationView: View {
    @Environment(AppState.self) private var app
    @Environment(WorkspacePreferences.self) private var preferences
    @State private var confirmReset = false

    var body: some View {
        List {
            if let user = app.user {
                Section {
                    Text("Deixe as ações mais usadas ao alcance. As preferências ficam neste aparelho, separadas por conta e clínica.").foregroundStyle(.secondary)
                }
                if user.canUseLARI {
                    Section {
                        ForEach(preferences.quickActions.filter { $0.isAllowed(for: user) }) { action in
                            HStack {
                                Label(action.title, systemImage: action.symbol)
                                Spacer()
                                Button { preferences.setQuickAction(action, enabled: false) } label: { Image(systemName: "minus.circle").foregroundStyle(.red) }
                                    .buttonStyle(.borderless).accessibilityLabel("Ocultar \(action.title)")
                            }.frame(minHeight: 44)
                        }.onMove { preferences.moveQuickActions(from: $0, to: $1) }
                        ForEach(ClinicalShortcut.allCases.filter { $0.isAllowed(for: user) && !preferences.quickActions.contains($0) }) { action in
                            Button { preferences.setQuickAction(action, enabled: true) } label: { Label("Mostrar \(action.title)", systemImage: "plus.circle") }.frame(minHeight: 44)
                        }
                    } header: { Text("Atalhos da tela Hoje") } footer: {
                        Text("Toque em Editar para mudar a ordem. As ações disponíveis respeitam seu perfil; LARI abre as tarefas e a assistência.")
                    }
                }
                Section("Conteúdo da tela Hoje") {
                    ForEach(HomeWidget.allCases.filter { $0 == .clinicalShortcuts ? user.canUseLARI : user.canReadAgenda }) { widget in
                        Toggle(widget.title, isOn: Binding(get: { preferences.homeWidgets.contains(widget) }, set: { preferences.setHomeWidget(widget, enabled: $0) }))
                    }
                }
                Section {
                    ForEach([WorkspaceDestination.today, .agenda, .patients].filter { $0.isAllowed(for: user) }) { destination in
                        Toggle(isOn: Binding(get: { preferences.destinations.contains(destination) }, set: { preferences.setDestination(destination, enabled: $0, user: user) })) {
                            Label(destination.title, systemImage: destination.symbol)
                        }
                    }
                    Label("Mais permanece disponível", systemImage: "ellipsis.circle").foregroundStyle(.secondary)
                } header: { Text("Abas principais") } footer: { Text("Até quatro abas. Todas as demais funções continuam acessíveis em Mais.") }
                Section {
                    ForEach(preferences.destinations.filter { $0 != .more }) { destination in Label(destination.title, systemImage: destination.symbol) }
                        .onMove { preferences.moveDestinations(from: $0, to: $1, user: user) }
                } header: { Text("Ordem das abas") }
                Section { Button("Restaurar minhas preferências", role: .destructive) { confirmReset = true } }
            }
        }.navigationTitle("Tela inicial e atalhos").inlineTitle()
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
        .confirmationDialog("Restaurar as preferências deste aparelho?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Restaurar padrão", role: .destructive) { if let user = app.user { preferences.reset(for: user) } }
            Button("Manter minhas preferências", role: .cancel) {}
        } message: { Text("A ordem dos atalhos, o conteúdo da tela Hoje e a aparência voltarão ao padrão para esta conta e clínica. Nenhum dado da clínica será apagado.") }
    }
}
