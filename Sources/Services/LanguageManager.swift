import Foundation
import SwiftUI

// MARK: - Language Manager

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case chineseSimplified = "zh-Hans"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .chineseSimplified: return "简体中文"
        }
    }
    
    var nativeName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .chineseSimplified: return "简体中文"
        }
    }
    
    var languageCode: String? {
        self == .system ? nil : rawValue
    }
}

// MARK: - Custom Bundle for Localization

extension Bundle {
    private static var bundleKey: UInt8 = 0
    
    /// Get the appropriate bundle for localization based on user's language preference
    static var localizedBundle: Bundle {
        // Check for stored language preference
        if let languageCode = UserDefaults.standard.string(forKey: "rssLanguage"),
           languageCode != "system",
           let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        
        // For Swift Package Manager, we need to find the resource bundle
        // The .module bundle is in the compiled resources
        if let resourceBundleURL = Bundle.main.url(forResource: "RussReader_RussReader", withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL) {
            
            // If we have a language preference, try to get that language from the resource bundle
            if let languageCode = UserDefaults.standard.string(forKey: "rssLanguage"),
               languageCode != "system",
               let path = resourceBundle.path(forResource: languageCode, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
            
            return resourceBundle
        }
        
        // Fallback to module bundle
        return .module
    }
}

// Helper to get localized strings with proper bundle
func LocalizedString(_ key: String) -> String {
    NSLocalizedString(key, bundle: .localizedBundle, comment: "")
}

// SwiftUI helper
struct LocalizedText: View {
    let key: String
    
    init(_ key: String) {
        self.key = key
    }
    
    var body: some View {
        Text(LocalizedString(key))
    }
}

