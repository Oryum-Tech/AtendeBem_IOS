import SwiftUI

// These previews contain no patient fixtures and perform no automatic login.
// PreviewProvider also works in command-line builds without Xcode preview macros.
struct LoginPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            LoginView().environment(AppState()).previewDisplayName("Entrar · Claro")
            LoginView().environment(AppState()).preferredColorScheme(.dark).previewDisplayName("Entrar · Escuro")
            LoginView().environment(AppState()).dynamicTypeSize(.accessibility3).previewDisplayName("Entrar · Texto ampliado")
        }
    }
}

struct ConnectionPreviews: PreviewProvider {
    static var previews: some View {
        List {
            ConnectionState(updatedAt: nil, error: nil, isLoading: true)
            ConnectionState(updatedAt: .now, error: nil, isLoading: false)
            ConnectionState(updatedAt: .now, error: "Sem conexão. A lista pode estar desatualizada.", isLoading: false)
        }.previewDisplayName("Estados de atualização")
    }
}
