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
    @State private var authType: AuthType = .none
    @State private var authUsername: String = ""
    @State private var authPassword: String = ""
    @State private var authToken: String = ""
    @State private var authExpanded: Bool = false

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

                DisclosureGroup(isExpanded: $authExpanded) {
                    Picker(String(localized: "Type", bundle: .module), selection: $authType) {
                        ForEach(AuthType.allCases, id: \.self) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.regular)
                    .padding(.top, 6)
                    
                    if authType == .basicAuth {
                        TextField(String(localized: "Username", bundle: .module), text: $authUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 24)
                        SecureField(String(localized: "Password", bundle: .module), text: $authPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 24)
                            .padding(.top, 4)
                    } else if authType == .bearerToken {
                        SecureField(String(localized: "API Key or Token", bundle: .module), text: $authToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 24)
                    }
                    
                    if authType != .none {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 9))
                            Text(String(localized: "Stored securely in Keychain. Only sent with feed requests.", bundle: .module))
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                } label: {
                    Text(String(localized: "Authentication", bundle: .module))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { authExpanded.toggle() }
                }
                .font(.system(size: 12))

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
        
        // Auto-convert YouTube URLs to RSS feeds
        if trimmed.contains("youtube.com") || trimmed.contains("youtu.be") {
            isDiscovering = true
            discoveredFeeds = []
            if let youtubeRSS = await convertYouTubeToRSS(trimmed) {
                await MainActor.run {
                    isDiscovering = false
                    discoveredFeeds = [youtubeRSS]
                }
                return
            }
            await MainActor.run { isDiscovering = false }
        }
        
        // Auto-convert Reddit URLs to RSS feeds
        if let redditRSS = convertRedditToRSS(trimmed) {
            await MainActor.run {
                discoveredFeeds = [redditRSS]
            }
            return
        }

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
    
    private func convertYouTubeToRSS(_ url: String) async -> DiscoveredFeed? {
        // Direct channel ID pattern: /channel/UCxxxxxx — no fetch needed
        if let range = url.range(of: #"/channel/(UC[a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let channelId = String(url[range]).replacingOccurrences(of: "/channel/", with: "")
            return DiscoveredFeed(
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)",
                title: "YouTube Channel",
                type: "Atom"
            )
        }
        
        // Playlist pattern: ?list=PLxxxxxx — no fetch needed
        if let range = url.range(of: #"[?&]list=([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let match = String(url[range])
            let playlistId = match.replacingOccurrences(of: "?list=", with: "").replacingOccurrences(of: "&list=", with: "")
            return DiscoveredFeed(
                url: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(playlistId)",
                title: "YouTube Playlist",
                type: "Atom"
            )
        }
        
        // For @handle, video URLs, or any other YouTube page — fetch and extract channel ID
        guard let pageURL = URL(string: url) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: pageURL)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            
            // Look for channel ID in the page HTML
            // Pattern 1: "channelId":"UCxxxx" (in JSON data)
            // Pattern 2: "externalId":"UCxxxx"
            // Pattern 3: <meta itemprop="channelId" content="UCxxxx">
            // Pattern 4: /channel/UCxxxx in canonical or RSS link
            let patterns = [
                #""channelId"\s*:\s*"(UC[a-zA-Z0-9_-]+)""#,
                #""externalId"\s*:\s*"(UC[a-zA-Z0-9_-]+)""#,
                #"content="(UC[a-zA-Z0-9_-]+)""#,
                #"/channel/(UC[a-zA-Z0-9_-]+)"#
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   match.numberOfRanges > 1,
                   let idRange = Range(match.range(at: 1), in: html) {
                    let channelId = String(html[idRange])
                    
                    // Extract channel name from page title if possible
                    var title = "YouTube Channel"
                    if let titleMatch = html.range(of: #"<title>(.+?)(?:\s*-\s*YouTube)?</title>"#, options: .regularExpression),
                       let innerRange = html.range(of: #"<title>(.+?)<"#, options: .regularExpression) {
                        let _ = titleMatch // suppress warning
                        let raw = String(html[innerRange]).replacingOccurrences(of: "<title>", with: "").replacingOccurrences(of: "<", with: "")
                        let cleaned = raw.replacingOccurrences(of: " - YouTube", with: "").trimmingCharacters(in: .whitespaces)
                        if !cleaned.isEmpty { title = cleaned }
                    }
                    
                    return DiscoveredFeed(
                        url: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)",
                        title: title,
                        type: "Atom"
                    )
                }
            }
        } catch {
            // Network error — fall through
        }
        
        return nil
    }
    
    private func convertRedditToRSS(_ url: String) -> DiscoveredFeed? {
        // Reddit subreddit: reddit.com/r/subreddit
        // Reddit user: reddit.com/user/username
        guard url.contains("reddit.com") else { return nil }
        
        // Subreddit pattern
        if let range = url.range(of: #"/r/([a-zA-Z0-9_]+)"#, options: .regularExpression) {
            let subreddit = String(url[range]).replacingOccurrences(of: "/r/", with: "")
            return DiscoveredFeed(
                url: "https://www.reddit.com/r/\(subreddit)/.rss",
                title: "r/\(subreddit)",
                type: "RSS"
            )
        }
        
        // User pattern
        if let range = url.range(of: #"/user/([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let username = String(url[range]).replacingOccurrences(of: "/user/", with: "")
            return DiscoveredFeed(
                url: "https://www.reddit.com/user/\(username)/.rss",
                title: "u/\(username)",
                type: "RSS"
            )
        }
        
        return nil
    }

    private func addFeed() {
        errorMessage = nil

        let cleanURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            errorMessage = String(localized: "This feed is already added.", bundle: .module)
            return
        }

        isDiscovering = true
        Task {
            let result = await store.addFeed(
                url: feedURL,
                title: feedTitle.isEmpty ? nil : feedTitle,
                authType: authType,
                username: authType == .basicAuth ? authUsername : nil,
                password: authType == .basicAuth ? authPassword : nil,
                token: authType == .bearerToken ? authToken : nil
            )
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
