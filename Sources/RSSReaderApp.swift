import SwiftUI

// MARK: - App Entry Point

@main
struct RSSReaderApp: App {
    @StateObject private var store = FeedStore()
    @AppStorage("rssStickyWindow") private var stickyWindow: Bool = true
    
    init() {
        // Apply stored language preference on app launch
        if let languageCode = UserDefaults.standard.string(forKey: "rssLanguage"),
           languageCode != "system" {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $stickyWindow) {
            RSSReaderView()
                .environmentObject(store)
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

        MenuBarExtra(isInserted: Binding(
            get: { !stickyWindow },
            set: { stickyWindow = !$0 }
        )) {
            RSSReaderView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.unreadCount > 0 ? "newspaper.fill" : "newspaper")
                if store.showUnreadBadge && store.unreadCount > 0 {
                    Text("\(store.unreadCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
        }
        .menuBarExtraStyle(.menu)
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
                .frame(minWidth: 350, maxWidth: 350)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
