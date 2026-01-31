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
        MenuBarExtra("RSS Reader", systemImage: store.unreadCount > 0 ? "newspaper.fill" : "newspaper") {
            RSSReaderView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environmentObject(store)
                .background(PanelAccessor().frame(width: 0, height: 0))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
