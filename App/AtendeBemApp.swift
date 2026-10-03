import SwiftUI
import AtendeBemUI

@main
struct AtendeBemApp: App {
    var body: some Scene {
        WindowGroup {
            AtendeBemRootView()
                .tint(Brand.accent)
        }
    }
}
