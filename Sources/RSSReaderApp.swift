import SwiftUI
import AppKit

// MARK: - Window Accessor for Z-ordering

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.level = .floating
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - App Entry Point

@main
struct RSSReaderApp: App {
    @StateObject private var store = FeedStore()
    @AppStorage("rssAppearanceMode") private var appearanceMode: String = "system"
    
    var body: some Scene {
        MenuBarExtra("RSS Reader", systemImage: store.unreadCount > 0 ? "newspaper.fill" : "newspaper") {
            RSSReaderView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
        
        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environmentObject(store)
                .background(WindowAccessor())
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
    
    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
