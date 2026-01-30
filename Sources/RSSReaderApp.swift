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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
