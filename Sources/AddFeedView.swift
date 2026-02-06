import SwiftUI
import AppKit

// MARK: - RSS Feed Discovery

struct DiscoveredFeed: Identifiable {
    let id = UUID()
    let url: String
    let title: String?
    let type: String
}

final class FeedDiscovery {
    static func discoverFeeds(from urlString: String) async -> [DiscoveredFeed] {
        // First check if it's already an RSS/Atom feed URL
        if urlString.contains("/feed") || urlString.contains("/rss") || urlString.contains(".xml") || urlString.contains(".atom") {
            return []
        }

        guard let url = URL(string: urlString) else { return [] }

        do {
            let request = URLRequest(url: url, timeoutInterval: defaultRequestTimeout)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return [] }

            return parseHTMLForFeeds(html: html, baseURL: url)
        } catch {
            return []
        }
    }

    private static func parseHTMLForFeeds(html: String, baseURL: URL) -> [DiscoveredFeed] {
        var feeds: [DiscoveredFeed] = []

        // Look for <link> tags with RSS/Atom feeds (attribute order varies by site)
        let allLinksPattern = #/<link[^>]+>/#
        let linkMatches = html.matches(of: allLinksPattern)

        for match in linkMatches {
            let linkTag = String(match.output)
            
            // Must have rel="alternate" and an RSS/Atom type
            guard linkTag.contains("alternate") else { continue }
            guard linkTag.contains("application/rss+xml") || linkTag.contains("application/atom+xml") else { continue }

            // Extract href using regex
            let hrefPattern = #/href=["']([^"']+)["']/#
            if let hrefMatch = linkTag.firstMatch(of: hrefPattern) {
                let hrefString = String(hrefMatch.output.1)

                // Extract title if present
                var title: String?
                let titlePattern = #/title=["']([^"']+)["']/#
                if let titleMatch = linkTag.firstMatch(of: titlePattern) {
                    title = String(titleMatch.output.1)
                }

                // Extract type
                var feedType = "RSS"
                if linkTag.contains("atom") {
                    feedType = "Atom"
                }

                // Make absolute URL if relative
                let absoluteURL: String
                if hrefString.hasPrefix("http") {
                    absoluteURL = hrefString
                } else if hrefString.hasPrefix("/") {
                    absoluteURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(hrefString)"
                } else {
                    absoluteURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")/\(hrefString)"
                }

                feeds.append(DiscoveredFeed(url: absoluteURL, title: title, type: feedType))
            }
        }

        // Also check common feed URLs as fallback
        if feeds.isEmpty {
            let commonPaths = ["/feed", "/rss", "/atom.xml", "/feed.xml", "/rss.xml", "/index.xml"]
            for path in commonPaths {
                let feedURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(path)"
                feeds.append(DiscoveredFeed(url: feedURL, title: nil, type: "RSS"))
            }
        }

        return feeds
    }
}

// MARK: - Add Feed Window (standalone window wrapper)

struct AddFeedWindow: View {
    @EnvironmentObject private var store: FeedStore
    @State private var isSheetPresented = true
    
    var body: some View {
        AddFeedSheet(isPresented: $isSheetPresented)
            .environmentObject(store)
            .onChange(of: isSheetPresented) { _, newValue in
                if !newValue {
                    // Sheet was dismissed, close the window
                    DispatchQueue.main.async {
                        // Try multiple ways to find and close the window
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" }) {
                            window.close()
                        } else if let window = NSApp.windows.first(where: { $0.title == "Add Feed" }) {
                            window.close()
                        } else {
                            // Fallback: close the key window if it looks like our add feed window
                            if let keyWindow = NSApp.keyWindow, keyWindow.level == .floating {
                                keyWindow.close()
                            }
                        }
                    }
                }
            }
            .frame(width: 350)
            .onAppear {
                // Reset state when window opens
                isSheetPresented = true
                
                // Configure window for proper input handling
                DispatchQueue.main.async {
                    configureAddFeedWindow()
                }
            }
    }
    
    private func configureAddFeedWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" || $0.title == "Add Feed" }) else { return }
        
        // Set identifier if not set
        if window.identifier == nil {
            window.identifier = NSUserInterfaceItemIdentifier("addFeed")
        }
        
        // CRITICAL: Temporarily change activation policy to allow keyboard input
        // LSUIElement apps can't receive keyboard events without this
        NSApp.setActivationPolicy(.regular)
        
        // Make it a floating panel
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.moveToActiveSpace)
        
        // Ensure it can become key and accept input
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Restore LSUIElement behavior when window closes
        // Using unique name to avoid duplicate observers
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Add Feed Sheet

struct AddFeedSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var isPresented: Bool
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    @State private var errorMessage: String?
    @State private var isDiscovering: Bool = false
    @State private var discoveredFeeds: [DiscoveredFeed] = []
    @State private var selectedDiscoveredFeed: DiscoveredFeed?

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Add Feed", bundle: .module))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Feed URL", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    FocusableTextField(text: $feedURL, placeholder: String(localized: "https://example.com/feed.xml", bundle: .module), shouldFocus: true)
                        .frame(height: 22)
                        .onChange(of: feedURL) { oldValue, newValue in
                            // Auto-detect feeds when URL changes
                            if newValue != oldValue && !newValue.isEmpty {
                                Task {
                                    await detectFeeds(from: newValue)
                                }
                            }
                        }

                    if isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                }

                // Show discovered feeds
                if !discoveredFeeds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Found RSS feeds:", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(discoveredFeeds.prefix(5)) { feed in
                            HStack(spacing: 6) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    if let title = feed.title {
                                        Text(title)
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    Text(feed.url)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button(String(localized: "Use", bundle: .module)) {
                                    feedURL = feed.url
                                    if let title = feed.title, feedTitle.isEmpty {
                                        feedTitle = title
                                    }
                                    discoveredFeeds = []
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                    Text(String(localized: "Title (optional)", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                FocusableTextField(text: $feedTitle, placeholder: String(localized: "My Feed", bundle: .module), shouldFocus: false)
                    .frame(height: 22)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }

            HStack {
                Button(String(localized: "Cancel", bundle: .module)) {
                    // Reset state and close
                    errorMessage = nil
                    isDiscovering = false
                    discoveredFeeds = []
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                if #available(macOS 26.0, *) {
                    Button(String(localized: "Add", bundle: .module)) {
                        addFeed()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscovering)
                } else {
                    Button(String(localized: "Add", bundle: .module)) {
                        addFeed()
                    }
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscovering)
                }
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            // CRITICAL: Change activation policy to allow keyboard input in sheets
            // LSUIElement apps need this to receive keyboard events
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            // Only restore LSUIElement behavior if no other regular windows are open
            // (e.g., if Preferences window is still open, keep .regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let hasVisibleWindows = NSApp.windows.contains { window in
                    window.isVisible && 
                    window.level == .normal && 
                    !window.className.contains("Sheet") &&
                    window.identifier?.rawValue != "addFeed"
                }
                
                if !hasVisibleWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private func detectFeeds(from urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only try to discover if it looks like a website URL
        guard trimmed.hasPrefix("http") && !trimmed.contains("/feed") && !trimmed.contains("/rss") && !trimmed.contains(".xml") && !trimmed.contains(".atom") else {
            return
        }

        isDiscovering = true
        discoveredFeeds = []

        let feeds = await FeedDiscovery.discoverFeeds(from: trimmed)

        await MainActor.run {
            isDiscovering = false
            discoveredFeeds = feeds
        }
    }

    private func addFeed() {
        errorMessage = nil

        let cleanURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            errorMessage = String(localized: "This feed is already added.", bundle: .module)
            return
        }

        // Show loading state and validate feed
        isDiscovering = true
        Task {
            let result = await store.addFeed(url: feedURL, title: feedTitle.isEmpty ? nil : feedTitle)
            await MainActor.run {
                isDiscovering = false
                if result.success {
                    isPresented = false
                } else {
                    errorMessage = result.errorMessage
                }
            }
        }
    }
}
