import SwiftUI

enum PreferencesAppearance {
    static func colorScheme(for appearanceMode: String, systemColorScheme: ColorScheme) -> ColorScheme {
        switch appearanceMode {
        case "dark": return .dark
        case "light": return .light
        default: return systemColorScheme
        }
    }

    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.12, green: 0.13, blue: 0.13)
        default:
            Color.white
        }
    }

    static func controlBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.17, green: 0.18, blue: 0.18)
        default:
            Color.white
        }
    }
}
