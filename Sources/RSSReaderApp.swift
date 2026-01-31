import SwiftUI
import AppKit

// MARK: - Floating Panel (properly handles focus for text input)

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Panel Accessor

struct PanelAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let currentWindow = view.window else { return }

            // Create panel with same frame
            let panel = FloatingPanel(
                contentRect: currentWindow.frame,
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.hidesOnDeactivate = false
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.styleMask.insert(.fullSizeContentView)

            // Transfer content
            if let contentView = currentWindow.contentView {
                panel.contentView = contentView
            }

            panel.center()
            panel.makeKeyAndOrderFront(nil)

            currentWindow.close()
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
        MenuBarExtra {
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
    }
}
