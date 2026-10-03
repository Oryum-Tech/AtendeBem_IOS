import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum Brand {
    // AtendeBem Design System: Green #0ABF77 + Blue #3B82F6.
    public static let primary = Color(red: 10 / 255, green: 191 / 255, blue: 119 / 255)
    public static let secondary = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)

    // Interactive tint uses an AA-safe shade in light mode and a brighter
    // brand shade in dark mode. Backgrounds remain system semantic surfaces.
    #if canImport(UIKit)
    public static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 47 / 255, green: 216 / 255, blue: 143 / 255, alpha: 1)
            : UIColor(red: 0 / 255, green: 124 / 255, blue: 81 / 255, alpha: 1)
    })
    #elseif canImport(AppKit)
    public static let accent = Color(nsColor: NSColor(
        calibratedRed: 0 / 255,
        green: 124 / 255,
        blue: 81 / 255,
        alpha: 1
    ))
    #else
    public static let accent = primary
    #endif

    #if canImport(UIKit)
    public static let background = Color(uiColor: .systemBackground)
    #elseif canImport(AppKit)
    public static let background = Color(nsColor: .windowBackgroundColor)
    #else
    public static let background = Color.white
    #endif
}

public struct BrandLogoView: View {
    public init() {}

    public var body: some View {
        Image("ATDBLogo", bundle: .module)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("AtendeBem")
    }
}
