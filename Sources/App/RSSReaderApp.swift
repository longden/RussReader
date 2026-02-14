import SwiftUI

// MARK: - App Entry Point

@main
struct RussReaderApp: App {
    @StateObject private var store = FeedStore()
    
    init() {
        // Apply stored language preference on app launch
        if let languageCode = UserDefaults.standard.string(forKey: "rssLanguage"),
           languageCode != "system" {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            RussReaderView()
                .environmentObject(store)
                .onAppear {
                    // Request notification permissions after app is initialized
                    store.setupNotifications()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.unreadCount > 0 ? "newspaper.fill" : "newspaper")
                if store.showUnreadBadge && store.unreadCount > 0 {
                    Text("\(store.unreadCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Suggested Feeds", id: "suggestedFeeds") {
            SuggestedFeedsSheet(isPresented: .constant(false), hideDoneButton: true)
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Add Feed", id: "addFeed") {
            AddFeedWindow()
                .environmentObject(store)
                .frame(minWidth: 420, maxWidth: 420)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            // Required for copy/paste to work in text fields (menu bar apps don't get Edit menu by default)
            CommandGroup(after: .appSettings) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    .keyboardShortcut("x", modifiers: .command)
                Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                    .keyboardShortcut("v", modifiers: .command)
                Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a", modifiers: .command)
            }
        }
    }
}
