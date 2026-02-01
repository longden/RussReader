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
    @Published var filterRules: [FilterRule] = []
    
    @AppStorage("rssHideReadItems") var hideReadItems: Bool = false
    @AppStorage("rssRefreshInterval") var refreshIntervalMinutes: Int = 30
    @AppStorage("rssMaxItemsPerFeed") var maxItemsPerFeed: Int = 50
    @AppStorage("rssFontSize") var fontSize: Double = 13
    @AppStorage("rssAppearanceMode") var appearanceMode: String = "system"
    @AppStorage("rssShowUnreadBadge") var showUnreadBadge: Bool = true
    @AppStorage("rssSmartFiltersEnabled") var smartFiltersEnabled: Bool = true
    @AppStorage("rssSelectedBrowser") var selectedBrowser: String = "default"
    @AppStorage("rssShowSummary") var showSummaryGlobal: Bool = false
    @AppStorage("rssLanguage") var selectedLanguage: String = "system"
    
    private let feedsKey = "rssFeeds"
    private let itemsKey = "rssItems"
    private let filterRulesKey = "rssFilterRules"
    private var refreshTimer: DispatchSourceTimer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.macbar", category: "RSSReader")
    private var saveWorkItem: DispatchWorkItem?
    private let maxTotalItems = 200
    private let itemRetentionDays = 30
    
    // Cache for filter results (per-item metadata like highlight color)
    private var filterResultsCache: [UUID: FilteredItemResult] = [:]
    
    var filteredItems: [FeedItem] {
        var result = items
        
        // Apply smart filters first (without side effects)
        if smartFiltersEnabled && !filterRules.isEmpty {
            let filterResults = computeFilterResults(for: result)
            result = filterResults.filter { $0.isVisible }.map { $0.item }
        }
        
        // Then apply view filter (all/unread/starred)
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
    
    var hiddenItemCount: Int {
        guard smartFiltersEnabled && !filterRules.isEmpty else { return 0 }
        let results = computeFilterResults(for: items)
        return results.filter { !$0.isVisible }.count
    }
    
    func highlightColor(for item: FeedItem) -> Color? {
        guard smartFiltersEnabled && !filterRules.isEmpty else { return nil }
        if let cached = filterResultsCache[item.id] {
            return cached.highlightColor
        }
        let results = computeFilterResults(for: [item])
        return results.first?.highlightColor
    }
    
    func iconEmoji(for item: FeedItem) -> String? {
        guard smartFiltersEnabled && !filterRules.isEmpty else { return nil }
        if let cached = filterResultsCache[item.id] {
            return cached.iconEmoji
        }
        let results = computeFilterResults(for: [item])
        return results.first?.iconEmoji
    }
    
    func shouldShowSummary(for item: FeedItem) -> Bool {
        // Show if global setting is on OR if filter says to show
        if showSummaryGlobal {
            return true
        }
        guard smartFiltersEnabled && !filterRules.isEmpty else { return false }
        if let cached = filterResultsCache[item.id] {
            return cached.shouldShowSummary
        }
        let results = computeFilterResults(for: [item])
        return results.first?.shouldShowSummary ?? false
    }
    
    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }
    
    var starredCount: Int {
        items.filter { $0.isStarred }.count
    }
    
    init() {
        load()
        loadFilterRules()
        
        // Purge old items only on app startup, not during refresh
        // This prevents deleting items the user just read
        purgeOldItems()
        
        startRefreshTimer()
        
        if feeds.isEmpty {
            addDefaultFeeds()
        }
    }
    
    deinit {
        refreshTimer?.cancel()
        saveWorkItem?.cancel()
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
        saveWorkItem?.cancel()
        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveImmediately()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: saveWorkItem!)
    }
    
    private func saveImmediately() {
        if let feedsData = try? JSONEncoder().encode(self.feeds) {
            UserDefaults.standard.set(feedsData, forKey: self.feedsKey)
        }
        if let itemsData = try? JSONEncoder().encode(self.items) {
            UserDefaults.standard.set(itemsData, forKey: self.itemsKey)
        } else {
            logger.error("Failed to encode items for save")
        }
    }
    
    // MARK: - Feed Management
    
    func addFeed(url: String, title: String? = nil) -> Bool {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return false }
        
        if feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            showError(String(localized: "This feed is already added.", bundle: .module))
            return false
        }
        
        let feed = Feed(title: title ?? cleanURL, url: cleanURL, customTitle: title != nil)
        feeds.append(feed)
        save()
        
        Task {
            await fetchFeed(feed)
        }
        
        return true
    }

    func addSuggestedFeeds(_ suggestedFeeds: [SuggestedFeed]) -> Int {
        var addedCount = 0
        for suggested in suggestedFeeds {
            let cleanURL = suggested.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanURL.isEmpty else { continue }
            guard !feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) else { continue }
            
            let feed = Feed(title: suggested.title, url: cleanURL, customTitle: true)
            feeds.append(feed)
            addedCount += 1
            
            Task { await fetchFeed(feed) }
        }
        
        if addedCount > 0 {
            save()
        }
        
        return addedCount
    }
    
    func removeFeed(_ feed: Feed) {
        feeds.removeAll { $0.id == feed.id }
        items.removeAll { $0.feedId == feed.id }
        save()
    }
    
    func feedTitle(for item: FeedItem) -> String {
        feeds.first { $0.id == item.feedId }?.title ?? String(localized: "Unknown", bundle: .module)
    }
    
    // MARK: - Item Management
    
    func markAsRead(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updatedItem = items[index]
        updatedItem.isRead = true
        items[index] = updatedItem
        objectWillChange.send()
        saveImmediately()
    }
    
    func markAsUnread(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updatedItem = items[index]
        updatedItem.isRead = false
        items[index] = updatedItem
        objectWillChange.send()
        saveImmediately()
    }
    
    func toggleStarred(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updatedItem = items[index]
        updatedItem.isStarred.toggle()
        items[index] = updatedItem
        objectWillChange.send()
        saveImmediately()
    }
    
    func toggleRead(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updatedItem = items[index]
        updatedItem.isRead.toggle()
        items[index] = updatedItem
        objectWillChange.send()
        saveImmediately()
    }
    
    func markAllAsRead() {
        items = items.map { item in
            var updated = item
            updated.isRead = true
            return updated
        }
        objectWillChange.send()
        saveImmediately()
    }
    
    func openItem(_ item: FeedItem) {
        markAsRead(item)
        if let url = URL(string: item.link) {
            if selectedBrowser == "default" {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: selectedBrowser), configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
    
    // MARK: - Refresh
    
    func startRefreshTimer() {
        refreshTimer?.cancel()
        let interval = DispatchTimeInterval.seconds(max(1, refreshIntervalMinutes) * 60)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
        timer.resume()
        refreshTimer = timer
    }
    
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Fetch feeds concurrently - network I/O happens off MainActor
        await withTaskGroup(of: (Feed, [FeedItem], String?, String?)?.self) { group in
            for feed in feeds {
                group.addTask { [weak self] in
                    await self?.fetchFeedData(feed)
                }
            }
            
            for await result in group {
                if let (feed, newItems, parsedTitle, parsedIconURL) = result {
                    processFetchedFeed(feed, items: newItems, parsedTitle: parsedTitle, parsedIconURL: parsedIconURL)
                }
            }
        }
        
        lastRefreshTime = Date()
        save()
    }
    
    // Network fetching - runs off MainActor for true concurrency
    nonisolated private func fetchFeedData(_ feed: Feed) async -> (Feed, [FeedItem], String?, String?)? {
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
            return (feed, newItems, parser.feedTitle, parser.feedIconURL)
        } catch {
            return nil
        }
    }
    
    // Process results on MainActor
    private func processFetchedFeed(_ feed: Feed, items newItems: [FeedItem], parsedTitle: String?, parsedIconURL: String?) {
        if let parsedTitle = parsedTitle, !parsedTitle.isEmpty {
            if let index = feeds.firstIndex(where: { $0.id == feed.id }), !feeds[index].customTitle {
                feeds[index].title = parsedTitle
            }
        }
        if let parsedIconURL = parsedIconURL, !parsedIconURL.isEmpty {
            if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
                feeds[index].iconURL = parsedIconURL
            }
        }
        if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
            feeds[index].lastFetched = Date()
        }
        
        // Build a lookup of existing items by key for efficient deduplication
        var existingItemsByKey: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            existingItemsByKey[itemKey(item)] = index
        }
        
        // Track which items are actually new
        var actuallyNewItems: [FeedItem] = []
        for newItem in newItems {
            let key = itemKey(newItem)
            if existingItemsByKey[key] == nil {
                // Item doesn't exist, add it
                items.append(newItem)
                actuallyNewItems.append(newItem)
                existingItemsByKey[key] = items.count - 1
            }
        }
        
        let feedItems = items.filter { $0.feedId == feed.id }
        if feedItems.count > maxItemsPerFeed {
            let sortedItems = feedItems.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            let toRemove = Set(sortedItems.dropFirst(maxItemsPerFeed).map { $0.id })
            items.removeAll { toRemove.contains($0.id) }
        }
        
        // Don't purge old items during refresh - it was deleting items the user just read!
        // purgeOldItems() is now only called on app startup
        cleanupFilterCache()
        
        // Apply auto-actions (star, mark read) to newly added items
        if smartFiltersEnabled && !filterRules.isEmpty && !actuallyNewItems.isEmpty {
            applyAutoActions(for: actuallyNewItems)
        }
        
        // Force UI update
        objectWillChange.send()
    }
    
    private func purgeOldItems() {
        // Only purge items that are BOTH old by publication date AND have been read
        // This should only be called on app startup, not during refresh
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -itemRetentionDays, to: Date()) ?? Date()
        
        items.removeAll { item in
            guard item.isRead && !item.isStarred else { return false }
            guard let pubDate = item.pubDate else { return false }
            return pubDate < cutoffDate
        }
        
        if items.count > maxTotalItems {
            let sortedItems = items.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            let unreadAndStarred = sortedItems.filter { !$0.isRead || $0.isStarred }
            let readItems = sortedItems.filter { $0.isRead && !$0.isStarred }
            
            let keepCount = maxTotalItems - unreadAndStarred.count
            let itemsToKeep = unreadAndStarred + readItems.prefix(max(0, keepCount))
            let keepIds = Set(itemsToKeep.map { $0.id })
            items.removeAll { !keepIds.contains($0.id) }
        }
    }
    
    func fetchFeed(_ feed: Feed) async {
        if let result = await fetchFeedData(feed) {
            processFetchedFeed(result.0, items: result.1, parsedTitle: result.2, parsedIconURL: result.3)
            save()
        } else {
            showError(String(localized: "Failed to fetch \(feed.title)", bundle: .module))
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
        // Normalize the key components for more reliable deduplication
        if let sourceId = item.sourceId, !sourceId.isEmpty {
            return "\(item.feedId.uuidString)-\(sourceId)"
        }
        if !item.link.isEmpty {
            // Normalize URL: remove trailing slashes and common tracking params
            let normalizedLink = normalizeURL(item.link)
            return "\(item.feedId.uuidString)-\(normalizedLink)"
        }
        let datePart = item.pubDate?.timeIntervalSince1970 ?? 0
        return "\(item.feedId.uuidString)-\(item.title.lowercased())-\(datePart)"
    }
    
    private func normalizeURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString.lowercased()
        }
        
        // Remove common tracking query parameters
        let trackingParams = Set(["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "ref", "source"])
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.filter { !trackingParams.contains($0.name.lowercased()) }
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
        }
        
        // Normalize path (remove trailing slash)
        if components.path.hasSuffix("/") && components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }
        
        // Return normalized URL string, lowercased for consistency
        return (components.string ?? urlString).lowercased()
    }
    
    // MARK: - Smart Filter Rules
    
    func loadFilterRules() {
        if let data = UserDefaults.standard.data(forKey: filterRulesKey),
           let decoded = try? JSONDecoder().decode([FilterRule].self, from: data) {
            filterRules = decoded
        }
    }
    
    func saveFilterRules() {
        if let data = try? JSONEncoder().encode(filterRules) {
            UserDefaults.standard.set(data, forKey: filterRulesKey)
        }
        invalidateFilterCache()
    }
    
    func addFilterRule(_ rule: FilterRule) {
        filterRules.append(rule)
        saveFilterRules()
    }
    
    func updateFilterRule(_ rule: FilterRule) {
        if let index = filterRules.firstIndex(where: { $0.id == rule.id }) {
            filterRules[index] = rule
            saveFilterRules()
        }
    }
    
    func deleteFilterRule(_ rule: FilterRule) {
        filterRules.removeAll { $0.id == rule.id }
        saveFilterRules()
    }
    
    func toggleFilterRule(_ rule: FilterRule) {
        if let index = filterRules.firstIndex(where: { $0.id == rule.id }) {
            filterRules[index].isEnabled.toggle()
            saveFilterRules()
        }
    }
    
    private func invalidateFilterCache() {
        filterResultsCache.removeAll()
    }
    
    // Clean stale cache entries for items that no longer exist
    private func cleanupFilterCache() {
        let currentItemIds = Set(items.map { $0.id })
        filterResultsCache = filterResultsCache.filter { currentItemIds.contains($0.key) }
    }
    
    // MARK: - Filter Engine
    
    /// Computes filter results WITHOUT side effects (pure function for display)
    private func computeFilterResults(for items: [FeedItem]) -> [FilteredItemResult] {
        let enabledRules = filterRules.filter { $0.isEnabled }
        guard !enabledRules.isEmpty else {
            return items.map { FilteredItemResult(item: $0) }
        }
        
        var results: [FilteredItemResult] = []
        let hasShowOnlyRule = enabledRules.contains { $0.action == .show }
        
        for item in items {
            var result = FilteredItemResult(item: item)
            var matchedShowRule = false
            
            for rule in enabledRules {
                // Check feed scope first
                if !ruleAppliesTo(rule, item: item) {
                    continue
                }
                
                let matches = evaluateRule(rule, for: item)
                
                if matches {
                    result.matchedRuleIds.insert(rule.id)
                    
                    switch rule.action {
                    case .show:
                        matchedShowRule = true
                    case .hide:
                        result.isVisible = false
                    case .highlight:
                        result.highlightColor = rule.effectiveColor
                    case .addIcon:
                        result.iconEmoji = rule.iconEmoji
                    case .addSummary:
                        result.shouldShowSummary = true
                    case .autoStar:
                        result.shouldAutoStar = true
                    case .markRead:
                        result.shouldMarkRead = true
                    }
                }
            }
            
            // If there are "show only" rules and this item didn't match any, hide it
            if hasShowOnlyRule && !matchedShowRule {
                result.isVisible = false
            }
            
            // Cache result for later lookups (highlight color, emoji, etc.)
            filterResultsCache[item.id] = result
            results.append(result)
        }
        
        return results
    }
    
    /// Apply auto-actions (star, mark read) for new items - call explicitly after fetch
    func applyAutoActions(for newItems: [FeedItem]) {
        let enabledRules = filterRules.filter { $0.isEnabled }
        guard !enabledRules.isEmpty else { return }
        
        var needsSave = false
        
        for item in newItems {
            for rule in enabledRules {
                if !ruleAppliesTo(rule, item: item) { continue }
                guard evaluateRule(rule, for: item) else { continue }
                
                if rule.action == .autoStar && !item.isStarred {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        var updatedItem = items[index]
                        updatedItem.isStarred = true
                        items[index] = updatedItem
                        needsSave = true
                    }
                }
                if rule.action == .markRead && !item.isRead {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        var updatedItem = items[index]
                        updatedItem.isRead = true
                        items[index] = updatedItem
                        needsSave = true
                    }
                }
            }
        }
        
        if needsSave {
            save()
        }
    }
    
    private func ruleAppliesTo(_ rule: FilterRule, item: FeedItem) -> Bool {
        switch rule.feedScope {
        case .allFeeds:
            return true
        case .specificFeeds(let feedIds):
            return feedIds.contains(item.feedId)
        }
    }
    
    private func evaluateRule(_ rule: FilterRule, for item: FeedItem) -> Bool {
        guard !rule.conditions.isEmpty else { return false }
        
        let conditionResults = rule.conditions.map { evaluateCondition($0, for: item) }
        
        switch rule.logic {
        case .all:
            return conditionResults.allSatisfy { $0 }
        case .any:
            return conditionResults.contains { $0 }
        }
    }
    
    private func evaluateCondition(_ condition: FilterCondition, for item: FeedItem) -> Bool {
        let searchText: String
        
        switch condition.field {
        case .title:
            searchText = item.title
        case .content:
            searchText = item.description
        case .author:
            searchText = item.author ?? ""
        case .link:
            searchText = item.link
        case .category:
            searchText = item.categories.joined(separator: " ")
        }
        
        let value = condition.value.lowercased()
        let text = searchText.lowercased()
        
        guard !value.isEmpty else { return false }
        
        switch condition.comparison {
        case .contains:
            return text.contains(value)
        case .notContains:
            return !text.contains(value)
        case .equals:
            return text == value
        case .startsWith:
            return text.hasPrefix(value)
        case .endsWith:
            return text.hasSuffix(value)
        }
    }
}

// MARK: - Browser Detection

struct BrowserInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    
    static func getInstalledBrowsers() -> [BrowserInfo] {
        var browsers: [BrowserInfo] = []
        var seenPaths = Set<String>()
        
        // Get default browser
        if let defaultBrowserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://")!) {
            let defaultName = defaultBrowserURL.deletingPathExtension().lastPathComponent
            browsers.append(BrowserInfo(
                id: "default",
                name: "System Default (\(defaultName))",
                path: "default"
            ))
            seenPaths.insert("default")
        } else {
            browsers.append(BrowserInfo(
                id: "default",
                name: "System Default",
                path: "default"
            ))
            seenPaths.insert("default")
        }
        
        // Get ALL applications that can open HTTP URLs
        if let httpURL = URL(string: "https://www.example.com"),
           let browserURLs = LSCopyApplicationURLsForURL(httpURL as CFURL, .all)?.takeRetainedValue() as? [URL] {
            
            for appURL in browserURLs {
                let appPath = appURL.path
                
                // Skip if already added
                guard !seenPaths.contains(appPath) else { continue }
                
                // Get app name from bundle or filename
                var appName = appURL.deletingPathExtension().lastPathComponent
                
                // Try to get better name from Info.plist
                if let bundle = Bundle(url: appURL),
                   let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? 
                                     bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                    appName = displayName
                }
                
                browsers.append(BrowserInfo(
                    id: appPath,
                    name: appName,
                    path: appPath
                ))
                seenPaths.insert(appPath)
            }
        }
        
        return browsers
    }
}
