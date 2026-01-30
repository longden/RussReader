import SwiftUI
import AppKit
import OSLog

// MARK: - Feed Store

@MainActor
final class FeedStore: ObservableObject {
    @Published var feeds: [Feed] = []
    @Published var items: [FeedItem] = []
    @Published var filter: FeedFilter = .all
    @Published var isRefreshing: Bool = false
    @Published var lastRefreshTime: Date?
    @Published var errorMessage: String?
    @Published var showingError: Bool = false
    
    @AppStorage("rssHideReadItems") var hideReadItems: Bool = false
    @AppStorage("rssRefreshInterval") var refreshIntervalMinutes: Int = 30
    @AppStorage("rssMaxItemsPerFeed") var maxItemsPerFeed: Int = 50
    @AppStorage("rssFontSize") var fontSize: Double = 13
    @AppStorage("rssAppearanceMode") var appearanceMode: String = "system"
    
    private let feedsKey = "rssFeeds"
    private let itemsKey = "rssItems"
    private var refreshTimer: Timer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.macbar", category: "RSSReader")
    
    var filteredItems: [FeedItem] {
        var result = items
        
        switch filter {
        case .all:
            break
        case .unread:
            result = result.filter { !$0.isRead }
        case .starred:
            result = result.filter { $0.isStarred }
        }
        
        if hideReadItems && filter == .all {
            result = result.filter { !$0.isRead || $0.isStarred }
        }
        
        result.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        
        return result
    }
    
    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }
    
    var starredCount: Int {
        items.filter { $0.isStarred }.count
    }
    
    init() {
        load()
        startRefreshTimer()
        
        if feeds.isEmpty {
            addDefaultFeeds()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    private func addDefaultFeeds() {
        let defaultFeeds = [
            Feed(title: "Daring Fireball", url: "https://daringfireball.net/feeds/main"),
            Feed(title: "Swift by Sundell", url: "https://www.swiftbysundell.com/rss"),
            Feed(title: "NSHipster", url: "https://nshipster.com/feed.xml")
        ]
        feeds = defaultFeeds
        save()
    }
    
    // MARK: - Persistence
    
    func load() {
        if let feedsData = UserDefaults.standard.data(forKey: feedsKey) {
            if let decoded = try? JSONDecoder().decode([Feed].self, from: feedsData) {
                feeds = decoded
            } else {
                logger.error("Failed to decode feeds from UserDefaults")
            }
        }
        
        if let itemsData = UserDefaults.standard.data(forKey: itemsKey) {
            if let decoded = try? JSONDecoder().decode([FeedItem].self, from: itemsData) {
                items = decoded
            } else {
                logger.error("Failed to decode items from UserDefaults")
            }
        }
    }
    
    func save() {
        if let feedsData = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(feedsData, forKey: feedsKey)
        }
        if let itemsData = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(itemsData, forKey: itemsKey)
        }
    }
    
    // MARK: - Feed Management
    
    func addFeed(url: String, title: String? = nil) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }
        
        if feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            showError("This feed is already added.")
            return
        }
        
        let feed = Feed(title: title ?? cleanURL, url: cleanURL)
        feeds.append(feed)
        save()
        
        Task {
            await fetchFeed(feed)
        }
    }
    
    func removeFeed(_ feed: Feed) {
        feeds.removeAll { $0.id == feed.id }
        items.removeAll { $0.feedId == feed.id }
        save()
    }
    
    func feedTitle(for item: FeedItem) -> String {
        feeds.first { $0.id == item.feedId }?.title ?? "Unknown"
    }
    
    // MARK: - Item Management
    
    func markAsRead(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isRead = true
        save()
    }
    
    func markAsUnread(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isRead = false
        save()
    }
    
    func toggleStarred(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isStarred.toggle()
        save()
    }
    
    func toggleRead(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isRead.toggle()
        save()
    }
    
    func markAllAsRead() {
        for i in items.indices {
            items[i].isRead = true
        }
        save()
    }
    
    func openItem(_ item: FeedItem) {
        markAsRead(item)
        if let url = URL(string: item.link) {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Refresh
    
    func startRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(1, refreshIntervalMinutes) * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
    }
    
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        // Fetch feeds concurrently - network I/O happens off MainActor
        await withTaskGroup(of: (Feed, [FeedItem], String?)?.self) { group in
            for feed in feeds {
                group.addTask { [weak self] in
                    await self?.fetchFeedData(feed)
                }
            }
            
            for await result in group {
                if let (feed, newItems, parsedTitle) = result {
                    processFetchedFeed(feed, items: newItems, parsedTitle: parsedTitle)
                }
            }
        }
        
        lastRefreshTime = Date()
        isRefreshing = false
        save()
    }
    
    // Network fetching - runs off MainActor for true concurrency
    nonisolated private func fetchFeedData(_ feed: Feed) async -> (Feed, [FeedItem], String?)? {
        guard let url = URL(string: feed.url) else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("macbar-rssreader/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                throw URLError(.badServerResponse)
            }
            let parser = RSSParser(feedId: feed.id)
            let newItems = parser.parse(data: data)
            return (feed, newItems, parser.feedTitle)
        } catch {
            return nil
        }
    }
    
    // Process results on MainActor
    private func processFetchedFeed(_ feed: Feed, items newItems: [FeedItem], parsedTitle: String?) {
        if let parsedTitle = parsedTitle, !parsedTitle.isEmpty {
            if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
                feeds[index].title = parsedTitle
            }
        }
        if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
            feeds[index].lastFetched = Date()
        }
        
        for newItem in newItems {
            if !items.contains(where: { itemKey($0) == itemKey(newItem) }) {
                items.append(newItem)
            }
        }
        
        let feedItems = items.filter { $0.feedId == feed.id }
        if feedItems.count > maxItemsPerFeed {
            let sortedItems = feedItems.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            let toRemove = Set(sortedItems.dropFirst(maxItemsPerFeed).map { $0.id })
            items.removeAll { toRemove.contains($0.id) }
        }
    }
    
    func fetchFeed(_ feed: Feed) async {
        if let result = await fetchFeedData(feed) {
            processFetchedFeed(result.0, items: result.1, parsedTitle: result.2)
            save()
        } else {
            showError("Failed to fetch \(feed.title)")
        }
    }
    
    // MARK: - OPML Import/Export
    
    func exportOPML() -> String {
        var opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>RSS Reader Feeds</title>
          </head>
          <body>
        """
        
        for feed in feeds {
            let escapedTitle = feed.title.replacingOccurrences(of: "\"", with: "&quot;")
            let escapedURL = feed.url.replacingOccurrences(of: "&", with: "&amp;")
            opml += """
            
                <outline type="rss" text="\(escapedTitle)" title="\(escapedTitle)" xmlUrl="\(escapedURL)" />
            """
        }
        
        opml += """
        
          </body>
        </opml>
        """
        
        return opml
    }
    
    func importOPML(from data: Data) {
        let parser = OPMLParser()
        let importedFeeds = parser.parse(data: data)
        
        var addedCount = 0
        for importedFeed in importedFeeds {
            if !feeds.contains(where: { $0.url.lowercased() == importedFeed.url.lowercased() }) {
                feeds.append(importedFeed)
                addedCount += 1
            }
        }
        
        save()
        
        if addedCount > 0 {
            Task {
                await refreshAll()
            }
        }
    }
    
    // MARK: - Error Handling
    
    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func itemKey(_ item: FeedItem) -> String {
        if let sourceId = item.sourceId, !sourceId.isEmpty {
            return "\(item.feedId.uuidString)-\(sourceId)"
        }
        if !item.link.isEmpty {
            return "\(item.feedId.uuidString)-\(item.link)"
        }
        let datePart = item.pubDate?.timeIntervalSince1970 ?? 0
        return "\(item.feedId.uuidString)-\(item.title.lowercased())-\(datePart)"
    }
}
