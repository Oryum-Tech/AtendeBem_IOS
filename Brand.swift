import SwiftUI

public enum Brand {
    // Core brand colors for AtendeBem (ATDB)
    public static let primary = Color(red: 0.02, green: 0.53, blue: 0.65)     // Teal-like primary
    public static let secondary = Color(red: 0.00, green: 0.37, blue: 0.47)   // Darker companion
    public static let accent = Color(red: 0.95, green: 0.49, blue: 0.13)      // Warm accent for highlights
    public static let background = Color(.systemBackground)
}

public struct BrandLogoView: View {
    public init() {}
    public var body: some View {
        if let uiImage = UIImage(named: "ATDBLogo") {
            Image(uiImage: uiImage).resizable().scaledToFit().accessibilityLabel("AtendeBem")
        } else {
            Label("AtendeBem", systemImage: "cross.case.fill")
        }
    }
}
