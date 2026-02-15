import SwiftUI
import AppKit
import OSLog

// MARK: - RSS Feed Discovery

struct DiscoveredFeed: Identifiable {
    let id = UUID()
    let url: String
    let title: String?
    let type: String
}

final class FeedDiscovery {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.macbar", category: "FeedDiscovery")

    /// Feed content types that indicate a URL is a direct feed
    private static let feedContentTypes = [
        "application/rss+xml", "application/atom+xml", "application/feed+json",
        "application/xml", "text/xml"
    ]
    
    static func discoverFeeds(from urlString: String) async -> [DiscoveredFeed] {
        guard let url = URL(string: urlString) else { return [] }

        do {
            var request = URLRequest(url: url, timeoutInterval: defaultRequestTimeout)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check Content-Type — if it's already a feed, return it directly
            if let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               feedContentTypes.contains(where: { contentType.contains($0) }) {
                let title = parseFeedTitle(from: data)
                let type = contentType.contains("atom") ? "Atom" : (contentType.contains("json") ? "JSON Feed" : "RSS")
                return [DiscoveredFeed(url: urlString, title: title, type: type)]
            }
            
            // Try parsing as feed directly (some servers return text/html for XML feeds)
            if let title = parseFeedTitle(from: data), looksLikeFeed(data: data) {
                let dataStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
                let type = dataStr.contains("<feed") ? "Atom" : (dataStr.contains("\"version\"") ? "JSON Feed" : "RSS")
                return [DiscoveredFeed(url: urlString, title: title, type: type)]
            }
            
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            
            var feeds = parseHTMLForFeeds(html: html, baseURL: url)
            
            // Fallback: try common feed paths
            if feeds.isEmpty {
                feeds = await probeCommonFeedPaths(baseURL: url)
            }
            
            return feeds
        } catch {
            logger.debug("Feed discovery failed for \(urlString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
    
    /// Check if data looks like an RSS/Atom/JSON feed
    private static func looksLikeFeed(data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return prefix.contains("<rss") || prefix.contains("<feed") || prefix.contains("<RDF") || 
               (prefix.hasPrefix("{") && prefix.contains("\"version\""))
    }
    
    /// Extract feed title from raw feed data
    private static func parseFeedTitle(from data: Data) -> String? {
        guard let str = String(data: data.prefix(2000), encoding: .utf8) else { return nil }
        // XML title
        if let match = str.firstMatch(of: #/<title>([^<]+)<\/title>/#) {
            let title = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        // JSON Feed title
        if let match = str.firstMatch(of: #/"title"\s*:\s*"([^"]+)"/#) {
            return String(match.output.1)
        }
        return nil
    }

    private static func parseHTMLForFeeds(html: String, baseURL: URL) -> [DiscoveredFeed] {
        var feeds: [DiscoveredFeed] = []

        // Look for <link> tags with RSS/Atom/JSON feeds
        let allLinksPattern = #/<link[^>]+>/#
        let linkMatches = html.matches(of: allLinksPattern)

        for match in linkMatches {
            let linkTag = String(match.output)
            
            // Must have rel="alternate" and a feed type
            guard linkTag.contains("alternate") else { continue }
            guard linkTag.contains("application/rss+xml") || linkTag.contains("application/atom+xml") || linkTag.contains("application/feed+json") else { continue }

            let hrefPattern = #/href=["']([^"']+)["']/#
            if let hrefMatch = linkTag.firstMatch(of: hrefPattern) {
                let hrefString = String(hrefMatch.output.1)

                var title: String?
                let titlePattern = #/title=["']([^"']+)["']/#
                if let titleMatch = linkTag.firstMatch(of: titlePattern) {
                    title = String(titleMatch.output.1)
                }

                var feedType = "RSS"
                if linkTag.contains("atom") {
                    feedType = "Atom"
                } else if linkTag.contains("feed+json") {
                    feedType = "JSON Feed"
                }

                let absoluteURL = makeAbsoluteURL(hrefString, base: baseURL)
                feeds.append(DiscoveredFeed(url: absoluteURL, title: title, type: feedType))
            }
        }

        return feeds
    }
    
    /// Probe common feed URL paths and return ones that respond with feed content
    private static func probeCommonFeedPaths(baseURL: URL) async -> [DiscoveredFeed] {
        let commonPaths = [
            "/feed", "/rss", "/atom.xml", "/feed.xml", "/rss.xml", "/index.xml",
            "/feed.json", "/atom", "/blog/feed", "/blog/rss", "/posts.rss", "/feed/rss"
        ]
        
        var feeds: [DiscoveredFeed] = []
        
        await withTaskGroup(of: DiscoveredFeed?.self) { group in
            for path in commonPaths {
                let feedURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(path)"
                group.addTask {
                    guard let url = URL(string: feedURL) else { return nil }
                    var request = URLRequest(url: url, timeoutInterval: 8)
                    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) {
                            // Verify it's actually a feed, not a generic 200 page
                            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                            let isFeedContentType = feedContentTypes.contains(where: { contentType.contains($0) })
                            let isFeedData = looksLikeFeed(data: data)
                            
                            if isFeedContentType || isFeedData {
                                let title = parseFeedTitle(from: data)
                                let dataStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
                                let type = dataStr.contains("<feed") ? "Atom" : (contentType.contains("json") || dataStr.contains("\"version\"") ? "JSON Feed" : "RSS")
                                return DiscoveredFeed(url: feedURL, title: title, type: type)
                            }
                        }
                    } catch {
                        logger.debug("Feed probe failed for \(feedURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                    return nil
                }
            }
            for await result in group {
                if let feed = result { feeds.append(feed) }
            }
        }
        
        return feeds
    }
    
    private static func makeAbsoluteURL(_ href: String, base: URL) -> String {
        if href.hasPrefix("http") {
            return href
        } else if href.hasPrefix("/") {
            return "\(base.scheme ?? "https")://\(base.host ?? "")\(href)"
        } else {
            return "\(base.scheme ?? "https")://\(base.host ?? "")/\(href)"
        }
    }
}

// MARK: - Add Feed Window (standalone window wrapper)

struct AddFeedWindow: View {
    @EnvironmentObject private var store: FeedStore
    @State private var isSheetPresented = true
    @State private var windowCloseObserver: NSObjectProtocol?
    
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
            .frame(width: 420)
            .onDisappear {
                if let observer = windowCloseObserver {
                    NotificationCenter.default.removeObserver(observer)
                    windowCloseObserver = nil
                }
            }
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
        // Keep observer token so we can remove it and avoid accumulating observers.
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
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
            Text(String(localized: "Add Feed"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Feed URL"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    FocusableTextField(text: $feedURL, placeholder: String(localized: "https://example.com/feed.xml"), shouldFocus: true)
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
                        Text(String(localized: "Found RSS feeds:"))
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

                                Button(String(localized: "Use")) {
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

                    Text(String(localized: "Title (optional)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                FocusableTextField(text: $feedTitle, placeholder: String(localized: "My Feed"), shouldFocus: false)
                    .frame(height: 22)

                DisclosureGroup(isExpanded: $authExpanded) {
                    Picker(String(localized: "Type"), selection: $authType) {
                        ForEach(AuthType.allCases, id: \.self) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.regular)
                    .padding(.top, 6)
                    
                    if authType == .basicAuth {
                        TextField(String(localized: "Username"), text: $authUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 24)
                        SecureField(String(localized: "Password"), text: $authPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 24)
                            .padding(.top, 4)
                    } else if authType == .bearerToken {
                        SecureField(String(localized: "API Key or Token"), text: $authToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 24)
                    }
                    
                    if authType != .none {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 9))
                            Text(String(localized: "Stored securely in Keychain. Only sent with feed requests."))
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                } label: {
                    Text(String(localized: "Authentication"))
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
                Button(String(localized: "Cancel")) {
                    // Reset state and close
                    errorMessage = nil
                    isDiscovering = false
                    discoveredFeeds = []
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                if #available(macOS 26.0, *) {
                    Button(String(localized: "Add")) {
                        addFeed()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscovering)
                } else {
                    Button(String(localized: "Add")) {
                        addFeed()
                    }
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscovering)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
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
        guard !trimmed.isEmpty else { return }

        // Skip re-detection if the URL is already a known feed URL (e.g. after clicking "Use")
        if trimmed.contains("/feeds/videos.xml") || trimmed.hasSuffix(".rss") || trimmed.hasSuffix("/feed") || trimmed.hasSuffix("/feed.xml") || trimmed.hasSuffix("/rss.xml") || trimmed.hasSuffix("/atom.xml") {
            return
        }

        let normalizedURL = normalizedURLForDetection(trimmed)
        
        // Platform-specific converters (instant, no network needed for most)
        
        // YouTube — always return from this block (don't fall through to Mastodon etc.)
        if normalizedURL.contains("youtube.com") || normalizedURL.contains("youtu.be") {
            isDiscovering = true
            discoveredFeeds = []
            if let youtubeRSS = await convertYouTubeToRSS(normalizedURL) {
                await MainActor.run {
                    isDiscovering = false
                    discoveredFeeds = [youtubeRSS]
                }
                return
            }
            // YouTube-specific conversion failed — try generic discovery as fallback
            let feeds = await FeedDiscovery.discoverFeeds(from: normalizedURL)
            await MainActor.run {
                isDiscovering = false
                discoveredFeeds = feeds
            }
            return
        }
        
        // Reddit
        if let redditRSS = convertRedditToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [redditRSS] }
            return
        }
        
        // GitHub
        if let githubFeeds = convertGitHubToRSS(normalizedURL), !githubFeeds.isEmpty {
            await MainActor.run { discoveredFeeds = githubFeeds }
            return
        }
        
        // Mastodon / Fediverse
        if let mastodonRSS = convertMastodonToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [mastodonRSS] }
            return
        }
        
        // Substack
        if let substackRSS = convertSubstackToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [substackRSS] }
            return
        }
        
        // Medium
        if let mediumRSS = convertMediumToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [mediumRSS] }
            return
        }
        
        // Tumblr
        if let tumblrRSS = convertTumblrToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [tumblrRSS] }
            return
        }
        
        // Hacker News
        if let hnFeeds = convertHackerNewsToRSS(normalizedURL), !hnFeeds.isEmpty {
            await MainActor.run { discoveredFeeds = hnFeeds }
            return
        }
        
        // WordPress.com
        if let wpRSS = convertWordPressToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [wpRSS] }
            return
        }
        
        // Blogger / Blogspot
        if let bloggerRSS = convertBloggerToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [bloggerRSS] }
            return
        }
        
        // Dev.to
        if let devtoRSS = convertDevToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [devtoRSS] }
            return
        }
        
        // Hashnode
        if let hashnodeRSS = convertHashnodeToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [hashnodeRSS] }
            return
        }
        
        // Ghost blogs (detect via common pattern)
        if let ghostRSS = convertGhostToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [ghostRSS] }
            return
        }
        
        // NPR
        if let nprFeeds = convertNPRToRSS(normalizedURL), !nprFeeds.isEmpty {
            await MainActor.run { discoveredFeeds = nprFeeds }
            return
        }
        
        // BBC News
        if let bbcFeeds = convertBBCToRSS(normalizedURL), !bbcFeeds.isEmpty {
            await MainActor.run { discoveredFeeds = bbcFeeds }
            return
        }
        
        // Stack Overflow
        if let soFeeds = convertStackOverflowToRSS(normalizedURL), !soFeeds.isEmpty {
            await MainActor.run { discoveredFeeds = soFeeds }
            return
        }
        
        // Bluesky
        if let bskyRSS = convertBlueskyToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [bskyRSS] }
            return
        }
        
        // GitLab
        if let gitlabFeeds = convertGitLabToRSS(normalizedURL), !gitlabFeeds.isEmpty {
            await MainActor.run { discoveredFeeds = gitlabFeeds }
            return
        }
        
        // Vimeo
        if let vimeoRSS = convertVimeoToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [vimeoRSS] }
            return
        }
        
        // Letterboxd
        if let letterboxdRSS = convertLetterboxdToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [letterboxdRSS] }
            return
        }
        
        // Product Hunt
        if let phRSS = convertProductHuntToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [phRSS] }
            return
        }
        
        // Pixelfed
        if let pixelfedRSS = convertPixelfedToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [pixelfedRSS] }
            return
        }
        
        // Lemmy
        if let lemmyRSS = convertLemmyToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [lemmyRSS] }
            return
        }
        
        // ArXiv
        if let arxivRSS = convertArXivToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [arxivRSS] }
            return
        }
        
        // Dribbble
        if let dribbbleRSS = convertDribbbleToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [dribbbleRSS] }
            return
        }
        
        // Bandcamp
        if let bandcampRSS = convertBandcampToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [bandcampRSS] }
            return
        }
        
        // Codeberg
        if let codebergRSS = convertCodebergToRSS(normalizedURL) {
            await MainActor.run { discoveredFeeds = [codebergRSS] }
            return
        }

        // Generic discovery — works for any URL
        let discoveryURL: String
        if normalizedURL.hasPrefix("http://") || normalizedURL.hasPrefix("https://") {
            discoveryURL = normalizedURL
        } else if normalizedURL.contains(".") {
            // Looks like a domain — auto-add https://
            discoveryURL = "https://\(normalizedURL)"
        } else {
            return
        }

        isDiscovering = true
        discoveredFeeds = []

        let feeds = await FeedDiscovery.discoverFeeds(from: discoveryURL)

        await MainActor.run {
            isDiscovering = false
            discoveredFeeds = feeds
        }
    }

    private func normalizedURLForDetection(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.contains(".") {
            return "https://\(trimmed)"
        }
        return trimmed
    }

    private func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
    
    private func convertYouTubeToRSS(_ url: String) async -> DiscoveredFeed? {
        let normalizedURL = normalizedURLForDetection(url)

        // Direct channel ID pattern: /channel/UCxxxxxx — no fetch needed
        if let channelId = firstRegexCapture(in: normalizedURL, pattern: #"/channel/(UC[a-zA-Z0-9_-]+)"#) {
            return DiscoveredFeed(
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)",
                title: "YouTube Channel",
                type: "Atom"
            )
        }
        
        // Playlist pattern: ?list=PLxxxxxx — no fetch needed
        if let playlistId = firstRegexCapture(in: normalizedURL, pattern: #"[?&]list=([a-zA-Z0-9_-]+)"#) {
            return DiscoveredFeed(
                url: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(playlistId)",
                title: "YouTube Playlist",
                type: "Atom"
            )
        }
        
        // For @handle, video URLs, or any other YouTube page — fetch and extract channel ID
        guard let pageURL = URL(string: normalizedURL) else { return nil }
        
        do {
            var request = URLRequest(url: pageURL, timeoutInterval: defaultRequestTimeout)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            // Bypass YouTube cookie consent wall (returns consent page without this)
            request.setValue("SOCS=CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjMwODI5LjA3X3AxGgJlbiACGgYIgJnPpwY; CONSENT=YES+1", forHTTPHeaderField: "Cookie")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            
            // Look for channel ID in the page HTML
            // Priority: RSS link tag > canonical link > externalId > meta tag > channelId (last — it matches related channels first)
            let patterns = [
                #"feeds/videos\.xml\?channel_id=(UC[a-zA-Z0-9_-]+)"#,
                #"<link[^>]*rel="canonical"[^>]*href="[^"]*/channel/(UC[a-zA-Z0-9_-]+)""#,
                #""externalId"\s*:\s*"(UC[a-zA-Z0-9_-]+)""#,
                #"<meta[^>]*itemprop="channelId"[^>]*content="(UC[a-zA-Z0-9_-]+)""#,
                #""browseId"\s*:\s*"(UC[a-zA-Z0-9_-]+)""#,
                #""channelId"\s*:\s*"(UC[a-zA-Z0-9_-]+)""#,
            ]

            var channelId: String?
            for pattern in patterns {
                if let found = firstRegexCapture(in: html, pattern: pattern) {
                    channelId = found
                    break
                }
            }

            if channelId == nil {
                let unescapedHTML = html.replacingOccurrences(of: #"\/"#, with: "/")
                for pattern in patterns {
                    if let found = firstRegexCapture(in: unescapedHTML, pattern: pattern) {
                        channelId = found
                        break
                    }
                }
            }

            if let channelId {
                var title = "YouTube Channel"
                if let extractedTitle = firstRegexCapture(in: html, pattern: #"<title>([^<]+)</title>"#) {
                    let cleaned = extractedTitle.replacingOccurrences(of: " - YouTube", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        title = cleaned
                    }
                }

                return DiscoveredFeed(
                    url: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)",
                    title: title,
                    type: "Atom"
                )
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

    // MARK: - GitHub Converter
    
    private func convertGitHubToRSS(_ url: String) -> [DiscoveredFeed]? {
        guard url.contains("github.com") else { return nil }
        
        // Match github.com/user/repo (with optional trailing path segments)
        guard let match = url.range(of: #"github\.com/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)"#, options: .regularExpression) else { return nil }
        let pathPart = String(url[match]).replacingOccurrences(of: "github.com/", with: "")
        let parts = pathPart.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let user = String(parts[0])
        let repo = String(parts[1])
        
        return [
            DiscoveredFeed(url: "https://github.com/\(user)/\(repo)/commits.atom", title: "\(user)/\(repo) — Commits", type: "Atom"),
            DiscoveredFeed(url: "https://github.com/\(user)/\(repo)/releases.atom", title: "\(user)/\(repo) — Releases", type: "Atom"),
            DiscoveredFeed(url: "https://github.com/\(user)/\(repo)/tags.atom", title: "\(user)/\(repo) — Tags", type: "Atom"),
        ]
    }
    
    // MARK: - Mastodon / Fediverse Converter
    
    private func convertMastodonToRSS(_ url: String) -> DiscoveredFeed? {
        // Pattern: https://instance.social/@username
        guard let urlObj = URL(string: url),
              let host = urlObj.host,
              let match = urlObj.path.range(of: #"^/@([a-zA-Z0-9_]+)/?$"#, options: .regularExpression) else { return nil }
        // Exclude known non-Mastodon sites
        let excluded = ["github.com", "twitter.com", "x.com", "medium.com", "youtube.com", "youtu.be"]
        guard !excluded.contains(host) else { return nil }
        
        let username = String(urlObj.path[match]).replacingOccurrences(of: "/@", with: "").replacingOccurrences(of: "/", with: "")
        return DiscoveredFeed(
            url: "https://\(host)/@\(username).rss",
            title: "@\(username)@\(host)",
            type: "RSS"
        )
    }
    
    // MARK: - Substack Converter
    
    private func convertSubstackToRSS(_ url: String) -> DiscoveredFeed? {
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        
        // Pattern: *.substack.com or custom domain with /p/ (Substack post pattern)
        if host.hasSuffix(".substack.com") {
            let subdomain = host.replacingOccurrences(of: ".substack.com", with: "")
            return DiscoveredFeed(
                url: "https://\(host)/feed",
                title: subdomain.capitalized,
                type: "RSS"
            )
        }
        return nil
    }
    
    // MARK: - Medium Converter
    
    private func convertMediumToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("medium.com") else { return nil }
        
        // Pattern: medium.com/@username
        if let match = url.range(of: #"medium\.com/@([a-zA-Z0-9_.-]+)"#, options: .regularExpression) {
            let userPart = String(url[match]).replacingOccurrences(of: "medium.com/", with: "")
            return DiscoveredFeed(
                url: "https://medium.com/feed/\(userPart)",
                title: "Medium — \(userPart)",
                type: "RSS"
            )
        }
        
        // Pattern: medium.com/publication-name
        if let urlObj = URL(string: url), let host = urlObj.host, host == "medium.com" {
            let path = urlObj.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty && !path.contains("/") {
                return DiscoveredFeed(
                    url: "https://medium.com/feed/\(path)",
                    title: "Medium — \(path)",
                    type: "RSS"
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Tumblr Converter
    
    private func convertTumblrToRSS(_ url: String) -> DiscoveredFeed? {
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        
        if host.hasSuffix(".tumblr.com") {
            let blogName = host.replacingOccurrences(of: ".tumblr.com", with: "")
            return DiscoveredFeed(
                url: "https://\(host)/rss",
                title: blogName.capitalized,
                type: "RSS"
            )
        }
        return nil
    }
    
    // MARK: - Hacker News Converter
    
    private func convertHackerNewsToRSS(_ url: String) -> [DiscoveredFeed]? {
        guard url.contains("news.ycombinator.com") || url.contains("hn.algolia.com") || url.contains("hacker-news") else { return nil }
        
        return [
            DiscoveredFeed(url: "https://hnrss.org/frontpage", title: "Hacker News — Front Page", type: "RSS"),
            DiscoveredFeed(url: "https://hnrss.org/newest", title: "Hacker News — New", type: "RSS"),
            DiscoveredFeed(url: "https://hnrss.org/best", title: "Hacker News — Best", type: "RSS"),
            DiscoveredFeed(url: "https://hnrss.org/show", title: "Hacker News — Show HN", type: "RSS"),
            DiscoveredFeed(url: "https://hnrss.org/ask", title: "Hacker News — Ask HN", type: "RSS"),
        ]
    }

    // MARK: - WordPress.com Converter
    
    private func convertWordPressToRSS(_ url: String) -> DiscoveredFeed? {
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        if host.hasSuffix(".wordpress.com") {
            let blogName = host.replacingOccurrences(of: ".wordpress.com", with: "")
            return DiscoveredFeed(url: "https://\(host)/feed", title: blogName.capitalized, type: "RSS")
        }
        return nil
    }
    
    // MARK: - Blogger / Blogspot Converter
    
    private func convertBloggerToRSS(_ url: String) -> DiscoveredFeed? {
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        if host.hasSuffix(".blogspot.com") || host.hasSuffix(".blogger.com") {
            let blogName = host.split(separator: ".").first.map(String.init) ?? host
            return DiscoveredFeed(url: "https://\(host)/feeds/posts/default", title: blogName.capitalized, type: "Atom")
        }
        return nil
    }
    
    // MARK: - Dev.to Converter
    
    private func convertDevToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("dev.to") else { return nil }
        if let urlObj = URL(string: url), let host = urlObj.host, host.contains("dev.to") {
            let path = urlObj.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty && !path.contains("/") {
                return DiscoveredFeed(url: "https://dev.to/feed/\(path)", title: "Dev.to — \(path)", type: "RSS")
            }
        }
        // Just dev.to homepage
        if url.hasSuffix("dev.to") || url.hasSuffix("dev.to/") {
            return DiscoveredFeed(url: "https://dev.to/feed", title: "Dev.to — Latest", type: "RSS")
        }
        return nil
    }
    
    // MARK: - Hashnode Converter
    
    private func convertHashnodeToRSS(_ url: String) -> DiscoveredFeed? {
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        if host.hasSuffix(".hashnode.dev") {
            let blogName = host.replacingOccurrences(of: ".hashnode.dev", with: "")
            return DiscoveredFeed(url: "https://\(host)/rss.xml", title: blogName.capitalized, type: "RSS")
        }
        return nil
    }
    
    // MARK: - Ghost Converter
    
    private func convertGhostToRSS(_ url: String) -> DiscoveredFeed? {
        // Ghost blogs use /rss/ — detect common Ghost hosting patterns
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        if host.hasSuffix(".ghost.io") {
            let blogName = host.replacingOccurrences(of: ".ghost.io", with: "")
            return DiscoveredFeed(url: "https://\(host)/rss/", title: blogName.capitalized, type: "RSS")
        }
        return nil
    }
    
    // MARK: - NPR Converter
    
    private func convertNPRToRSS(_ url: String) -> [DiscoveredFeed]? {
        guard url.contains("npr.org") else { return nil }
        return [
            DiscoveredFeed(url: "https://feeds.npr.org/1001/rss.xml", title: "NPR — News", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.npr.org/1002/rss.xml", title: "NPR — World", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.npr.org/1014/rss.xml", title: "NPR — Politics", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.npr.org/1019/rss.xml", title: "NPR — Technology", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.npr.org/1007/rss.xml", title: "NPR — Science", type: "RSS"),
        ]
    }
    
    // MARK: - BBC News Converter
    
    private func convertBBCToRSS(_ url: String) -> [DiscoveredFeed]? {
        guard url.contains("bbc.com") || url.contains("bbc.co.uk") else { return nil }
        return [
            DiscoveredFeed(url: "https://feeds.bbci.co.uk/news/rss.xml", title: "BBC — Top Stories", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.bbci.co.uk/news/world/rss.xml", title: "BBC — World", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.bbci.co.uk/news/technology/rss.xml", title: "BBC — Technology", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", title: "BBC — Science", type: "RSS"),
            DiscoveredFeed(url: "https://feeds.bbci.co.uk/news/business/rss.xml", title: "BBC — Business", type: "RSS"),
        ]
    }
    
    // MARK: - Stack Overflow Converter
    
    private func convertStackOverflowToRSS(_ url: String) -> [DiscoveredFeed]? {
        guard url.contains("stackoverflow.com") else { return nil }
        
        // Tag-specific feed: stackoverflow.com/questions/tagged/swift
        if let match = url.range(of: #"tagged/([a-zA-Z0-9_.+-]+)"#, options: .regularExpression) {
            let tag = String(url[match]).replacingOccurrences(of: "tagged/", with: "")
            return [
                DiscoveredFeed(url: "https://stackoverflow.com/feeds/tag/\(tag)", title: "Stack Overflow — [\(tag)]", type: "Atom"),
            ]
        }
        
        // Question-specific feed
        if let match = url.range(of: #"questions/(\d+)"#, options: .regularExpression) {
            let qid = String(url[match]).replacingOccurrences(of: "questions/", with: "")
            return [
                DiscoveredFeed(url: "https://stackoverflow.com/feeds/question/\(qid)", title: "Stack Overflow — Question #\(qid)", type: "Atom"),
            ]
        }
        
        // General SO feeds
        return [
            DiscoveredFeed(url: "https://stackoverflow.com/feeds", title: "Stack Overflow — Recent Questions", type: "Atom"),
        ]
    }
    
    // MARK: - Bluesky Converter
    
    private func convertBlueskyToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("bsky.app") else { return nil }
        
        // Pattern: bsky.app/profile/username.bsky.social or bsky.app/profile/custom.domain
        if let match = url.range(of: #"profile/([a-zA-Z0-9_.-]+)"#, options: .regularExpression) {
            let handle = String(url[match]).replacingOccurrences(of: "profile/", with: "")
            // Use public Bluesky RSS bridge
            return DiscoveredFeed(
                url: "https://bsky.app/profile/\(handle)/rss",
                title: "Bluesky — @\(handle)",
                type: "RSS"
            )
        }
        return nil
    }
    
    // MARK: - GitLab Converter
    
    private func convertGitLabToRSS(_ url: String) -> [DiscoveredFeed]? {
        guard url.contains("gitlab.com") else { return nil }
        
        guard let match = url.range(of: #"gitlab\.com/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)"#, options: .regularExpression) else { return nil }
        let pathPart = String(url[match]).replacingOccurrences(of: "gitlab.com/", with: "")
        let parts = pathPart.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let user = String(parts[0])
        let repo = String(parts[1])
        
        return [
            DiscoveredFeed(url: "https://gitlab.com/\(user)/\(repo)/-/commits/main.atom", title: "\(user)/\(repo) — Commits", type: "Atom"),
            DiscoveredFeed(url: "https://gitlab.com/\(user)/\(repo)/-/tags.atom", title: "\(user)/\(repo) — Releases", type: "Atom"),
        ]
    }
    
    // MARK: - Vimeo Converter
    
    private func convertVimeoToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("vimeo.com") else { return nil }
        
        let reserved = ["categories", "channels", "watch", "about", "settings", "login", "explore", "search", "features", "upload", "help"]
        if let match = url.range(of: #"vimeo\.com/([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let username = String(url[match]).replacingOccurrences(of: "vimeo.com/", with: "")
            guard !reserved.contains(username.lowercased()) else { return nil }
            return DiscoveredFeed(
                url: "https://vimeo.com/\(username)/videos/rss",
                title: "Vimeo — \(username)",
                type: "RSS"
            )
        }
        return nil
    }
    
    // MARK: - Letterboxd Converter
    
    private func convertLetterboxdToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("letterboxd.com") else { return nil }
        
        let reserved = ["film", "films", "list", "lists", "about", "settings", "login", "explore", "search", "activity", "members"]
        if let match = url.range(of: #"letterboxd\.com/([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let username = String(url[match]).replacingOccurrences(of: "letterboxd.com/", with: "")
            guard !reserved.contains(username.lowercased()) else { return nil }
            return DiscoveredFeed(
                url: "https://letterboxd.com/\(username)/rss/",
                title: "Letterboxd — \(username)",
                type: "RSS"
            )
        }
        return nil
    }
    
    // MARK: - Product Hunt Converter
    
    private func convertProductHuntToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("producthunt.com") else { return nil }
        return DiscoveredFeed(
            url: "https://www.producthunt.com/feed",
            title: "Product Hunt",
            type: "RSS"
        )
    }
    
    // MARK: - Pixelfed Converter
    
    private func convertPixelfedToRSS(_ url: String) -> DiscoveredFeed? {
        let instances = ["pixelfed.social", "pixelfed.de", "pixel.tchncs.de", "pxl.mx"]
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        guard instances.contains(host) else { return nil }
        
        let parts = urlObj.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let username: String?
        if parts.count == 1 {
            username = parts[0]
        } else if parts.count == 2, parts[0] == "users" {
            username = parts[1]
        } else {
            username = nil
        }
        guard let username, username != "users" else { return nil }
        return DiscoveredFeed(
            url: "https://\(host)/users/\(username).atom",
            title: "Pixelfed — @\(username)@\(host)",
            type: "Atom"
        )
    }
    
    // MARK: - Lemmy Converter
    
    private func convertLemmyToRSS(_ url: String) -> DiscoveredFeed? {
        let instances = ["lemmy.world", "lemmy.ml", "lemmy.dbzer0.com", "programming.dev", "sh.itjust.works", "beehaw.org"]
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        guard instances.contains(host) else { return nil }
        
        // Community feed
        if let match = url.range(of: #"/c/([a-zA-Z0-9_.-]+)"#, options: .regularExpression) {
            let community = String(url[match]).replacingOccurrences(of: "/c/", with: "")
            return DiscoveredFeed(
                url: "https://\(host)/feeds/c/\(community).xml?sort=New",
                title: "Lemmy — \(community)@\(host)",
                type: "RSS"
            )
        }
        
        // User feed
        if let match = url.range(of: #"/u/([a-zA-Z0-9_.-]+)"#, options: .regularExpression) {
            let user = String(url[match]).replacingOccurrences(of: "/u/", with: "")
            return DiscoveredFeed(
                url: "https://\(host)/feeds/u/\(user).xml?sort=New",
                title: "Lemmy — u/\(user)@\(host)",
                type: "RSS"
            )
        }
        
        return nil
    }
    
    // MARK: - ArXiv Converter
    
    private func convertArXivToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("arxiv.org") else { return nil }
        
        // Category listing: arxiv.org/list/cs.AI or arxiv.org/list/math.CO
        if let match = url.range(of: #"arxiv\.org/list/([a-zA-Z-]+\.[a-zA-Z]+)"#, options: .regularExpression) {
            let category = String(url[match]).replacingOccurrences(of: "arxiv.org/list/", with: "")
            return DiscoveredFeed(
                url: "https://export.arxiv.org/rss/\(category)",
                title: "ArXiv — \(category)",
                type: "RSS"
            )
        }
        
        return nil
    }
    
    // MARK: - Dribbble Converter
    
    private func convertDribbbleToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("dribbble.com") else { return nil }
        
        let reserved = ["shots", "tags", "about", "settings", "login", "explore", "search", "signup", "stories"]
        if let match = url.range(of: #"dribbble\.com/([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let username = String(url[match]).replacingOccurrences(of: "dribbble.com/", with: "")
            guard !reserved.contains(username.lowercased()) else { return nil }
            return DiscoveredFeed(
                url: "https://dribbble.com/\(username)/shots.rss",
                title: "Dribbble — \(username)",
                type: "RSS"
            )
        }
        return nil
    }
    
    // MARK: - Bandcamp Converter
    
    private func convertBandcampToRSS(_ url: String) -> DiscoveredFeed? {
        guard let urlObj = URL(string: url), let host = urlObj.host else { return nil }
        
        guard host.hasSuffix(".bandcamp.com") else { return nil }
        let artist = host.replacingOccurrences(of: ".bandcamp.com", with: "")
        guard !artist.isEmpty else { return nil }
        return DiscoveredFeed(
            url: "https://\(artist).bandcamp.com/feed",
            title: "Bandcamp — \(artist)",
            type: "RSS"
        )
    }
    
    // MARK: - Codeberg Converter
    
    private func convertCodebergToRSS(_ url: String) -> DiscoveredFeed? {
        guard url.contains("codeberg.org") else { return nil }
        
        guard let match = url.range(of: #"codeberg\.org/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)"#, options: .regularExpression) else { return nil }
        let pathPart = String(url[match]).replacingOccurrences(of: "codeberg.org/", with: "")
        let parts = pathPart.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let user = String(parts[0])
        let repo = String(parts[1])
        
        return DiscoveredFeed(
            url: "https://codeberg.org/\(user)/\(repo).atom",
            title: "\(user)/\(repo) — Codeberg",
            type: "Atom"
        )
    }

    private func addFeed() {
        errorMessage = nil

        // If a platform-specific feed was discovered (e.g. YouTube → RSS), use it
        let urlToAdd: String
        var titleToUse = feedTitle
        if let discovered = discoveredFeeds.first {
            urlToAdd = discovered.url
            if titleToUse.isEmpty, let title = discovered.title {
                titleToUse = title
            }
        } else {
            urlToAdd = feedURL
        }

        let cleanURL = urlToAdd.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            errorMessage = String(localized: "This feed is already added.")
            return
        }

        isDiscovering = true
        Task {
            let result = await store.addFeed(
                url: urlToAdd,
                title: titleToUse.isEmpty ? nil : titleToUse,
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
