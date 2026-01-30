import SwiftUI
import AppKit

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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
