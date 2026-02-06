import SwiftUI
import AppKit
import OSLog
@preconcurrency import UserNotifications
import CoreFoundation

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
    @AppStorage("rssTitleMaxLines") var titleMaxLines: Int = 2
    @AppStorage("rssTimeFormat") var timeFormat: String = "12h"
    @AppStorage("rssAppearanceMode") var appearanceMode: String = "system"
    @AppStorage("rssShowUnreadBadge") var showUnreadBadge: Bool = true
    @AppStorage("rssSmartFiltersEnabled") var smartFiltersEnabled: Bool = true
    @AppStorage("rssSelectedBrowser") var selectedBrowser: String = "default"
    @AppStorage("rssShowSummary") var showSummaryGlobal: Bool = false
    @AppStorage("rssLanguage") var selectedLanguage: String = "system"
    @AppStorage("rssStickyWindow") var stickyWindow: Bool = true
    @AppStorage("rssNewItemNotifications") var newItemNotificationsEnabled: Bool = false
    @AppStorage("rssShowFeedIcons") var showFeedIcons: Bool = false
    
    private let feedsKey = "rssFeeds"
    private let itemsKey = "rssItems"
    private let filterRulesKey = "rssFilterRules"
    private var refreshTimer: DispatchSourceTimer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.macbar", category: "RSSReader")
    private var saveWorkItem: DispatchWorkItem?
    private let maxTotalItems = 200
    private let itemRetentionDays = 30
    private let requestTimeout: TimeInterval = 15
    
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
    
    /// Call this after app is fully initialized to request notification permissions
    func setupNotifications() {
        Task {
            await requestNotificationPermissions()
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
                showError(String(localized: "Failed to load feeds. Your saved data may be corrupted.", bundle: .module))
            }
        }
        
        if let itemsData = UserDefaults.standard.data(forKey: itemsKey) {
            if let decoded = try? JSONDecoder().decode([FeedItem].self, from: itemsData) {
                items = decoded
            } else {
                logger.error("Failed to decode items from UserDefaults")
                showError(String(localized: "Failed to load items. Your saved data may be corrupted.", bundle: .module))
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
        } else {
            logger.error("Failed to encode feeds for save")
            showError(String(localized: "Failed to save feeds. Please check available disk space.", bundle: .module))
        }
        if let itemsData = try? JSONEncoder().encode(self.items) {
            UserDefaults.standard.set(itemsData, forKey: self.itemsKey)
        } else {
            logger.error("Failed to encode items for save")
            showError(String(localized: "Failed to save items. Please check available disk space.", bundle: .module))
        }
    }
    
    // MARK: - Feed Management
    
    func addFeed(url: String, title: String? = nil) async -> (success: Bool, errorMessage: String?) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return (false, String(localized: "Feed URL cannot be empty.", bundle: .module)) }
        
        if feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            return (false, String(localized: "This feed is already added.", bundle: .module))
        }
        
        // Validate the feed by attempting to fetch it first
        let tempFeed = Feed(title: title ?? cleanURL, url: cleanURL, customTitle: title != nil)
        guard let result = await fetchFeedData(tempFeed) else {
            return (false, String(localized: "Unable to fetch feed. Please check the URL and try again.", bundle: .module))
        }
        
        let (_, fetchedItems, parsedTitle, parsedIconURL, eTag, lastModified) = result
        
        // Ensure we got at least some items
        guard !fetchedItems.isEmpty else {
            return (false, String(localized: "No items found in feed. The URL may not be a valid RSS/Atom feed.", bundle: .module))
        }
        
        // Feed is valid, add it to the list
        var feed = tempFeed
        if let parsedTitle = parsedTitle, !parsedTitle.isEmpty, !feed.customTitle {
            feed.title = parsedTitle
        }
        if let parsedIconURL = parsedIconURL, !parsedIconURL.isEmpty {
            feed.iconURL = parsedIconURL
        }
        feed.lastFetched = Date()
        if let eTag = eTag, !eTag.isEmpty {
            feed.eTag = eTag
        }
        if let lastModified = lastModified, !lastModified.isEmpty {
            feed.lastModified = lastModified
        }
        
        feeds.append(feed)
        
        // Add the fetched items (limited by maxItemsPerFeed)
        let itemsToAdd = Array(fetchedItems.prefix(maxItemsPerFeed))
        for item in itemsToAdd {
            let key = itemKey(item)
            if !items.contains(where: { itemKey($0) == key }) {
                items.append(item)
            }
        }
        
        save()
        return (true, nil)
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
        cleanupFilterCache()
        save()
    }
    
    func feedTitle(for item: FeedItem) -> String {
        feeds.first { $0.id == item.feedId }?.title ?? String(localized: "Unknown", bundle: .module)
    }

    func feedIconURL(for item: FeedItem) -> String? {
        feeds.first { $0.id == item.feedId }?.iconURL
    }

    func feedURL(for item: FeedItem) -> String? {
        feeds.first { $0.id == item.feedId }?.url
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
        cleanupFilterCache()
        saveImmediately()
    }

    func markItemsAboveAsRead(_ item: FeedItem) {
        let orderedItems = filteredItems
        guard let index = orderedItems.firstIndex(where: { $0.id == item.id }) else { return }
        let idsToMark = Set(orderedItems.prefix(index).map { $0.id })
        guard !idsToMark.isEmpty else { return }
        items = items.map { current in
            guard idsToMark.contains(current.id) else { return current }
            var updated = current
            updated.isRead = true
            return updated
        }
        objectWillChange.send()
        cleanupFilterCache()
        saveImmediately()
    }

    func markItemsBelowAsRead(_ item: FeedItem) {
        let orderedItems = filteredItems
        guard let index = orderedItems.firstIndex(where: { $0.id == item.id }) else { return }
        let idsToMark = Set(orderedItems.suffix(from: index + 1).map { $0.id })
        guard !idsToMark.isEmpty else { return }
        items = items.map { current in
            guard idsToMark.contains(current.id) else { return current }
            var updated = current
            updated.isRead = true
            return updated
        }
        objectWillChange.send()
        cleanupFilterCache()
        saveImmediately()
    }

    func clearItems() {
        items.removeAll()
        filterResultsCache.removeAll()
        lastRefreshTime = nil
        save()
    }
    
    func openItem(_ item: FeedItem) {
        markAsRead(item)
        
        // Prefer enclosure URL (podcast audio, video) over article link
        let targetLink: String
        if let firstEnclosure = item.enclosures.first, !firstEnclosure.url.isEmpty {
            targetLink = firstEnclosure.url
        } else {
            targetLink = item.link
        }
        
        // Clean and validate URL
        let cleanLink = targetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanLink), 
              (url.scheme == "http" || url.scheme == "https") else { 
            logger.error("Invalid URL: \(targetLink)")
            return 
        }
        
        if selectedBrowser == "default" {
            NSWorkspace.shared.open(url)
        } else {
            // Try to open with selected browser, fall back to default if it fails
            let browserURL = URL(fileURLWithPath: selectedBrowser)
            let config = NSWorkspace.OpenConfiguration()
            
            NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: config) { _, error in
                if error != nil {
                    self.logger.error("Failed to open in selected browser: \(error?.localizedDescription ?? "unknown error", privacy: .public)")
                    // Fall back to default browser if selected browser fails
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    func shareItem(_ item: FeedItem) {
        let cleanLink = item.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanLink),
              (url.scheme == "http" || url.scheme == "https") else {
            logger.error("Invalid URL: \(item.link)")
            showError(String(localized: "Cannot share this item because its link is invalid.", bundle: .module))
            return
        }

        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemsToShare: [Any] = title.isEmpty ? [url] : [title, url]
        let picker = NSSharingServicePicker(items: itemsToShare)
        guard let targetView = (NSApp.keyWindow ?? NSApp.windows.first)?.contentView else {
            showError(String(localized: "Unable to open the share menu right now.", bundle: .module))
            return
        }
        picker.show(relativeTo: targetView.bounds, of: targetView, preferredEdge: .minY)
    }
    
    // MARK: - Notifications
    
    nonisolated func requestNotificationPermissions() async {
        // Guard against environments where notifications aren't available (e.g., swift run)
        guard Bundle.main.bundleIdentifier != nil else {
            await MainActor.run {
                logger.info("Skipping notification setup - no bundle identifier (likely swift run)")
            }
            return
        }
        
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                await MainActor.run {
                    logger.warning("Notification permissions denied by user")
                }
            }
        } catch {
            await MainActor.run {
                logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            }
        }
    }
    
    func sendNotification(for item: FeedItem, ruleName: String) {
        guard newItemNotificationsEnabled else { return }
        
        // Guard against environments where notifications aren't available
        guard Bundle.main.bundleIdentifier != nil else {
            logger.debug("Skipping notification - no bundle identifier")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = ruleName
        content.body = item.title
        content.sound = .default
        
        // Add feed name as subtitle if available
        if let feed = feeds.first(where: { $0.id == item.feedId }) {
            content.subtitle = feed.title
        }
        
        // Store item link in userInfo for click handling
        content.userInfo = ["itemLink": item.link, "itemId": item.id.uuidString]
        
        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Refresh
    
    func startRefreshTimer() {
        refreshTimer?.cancel()
        
        // If refresh interval is 0 (manual), don't start a timer
        guard refreshIntervalMinutes > 0 else { return }
        
        let interval = DispatchTimeInterval.seconds(refreshIntervalMinutes * 60)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            Task { await self?.refreshAll() }
        }
        timer.resume()
        refreshTimer = timer
    }
    
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let previousUnreadCount = unreadCount
        
        // Fetch feeds concurrently - network I/O happens off MainActor
        let maxConcurrentFetches = 6
        await withTaskGroup(of: (Feed, [FeedItem], String?, String?, String?, String?)?.self) { group in
            var feedIterator = feeds.makeIterator()
            var activeTasks = 0

            func enqueueNext() {
                guard let feed = feedIterator.next() else { return }
                activeTasks += 1
                group.addTask { [weak self] in
                    await self?.fetchFeedData(feed)
                }
            }

            for _ in 0..<min(maxConcurrentFetches, feeds.count) {
                enqueueNext()
            }
            
            for await result in group {
                activeTasks -= 1
                if let (feed, newItems, parsedTitle, parsedIconURL, eTag, lastModified) = result {
                    processFetchedFeed(feed, items: newItems, parsedTitle: parsedTitle, parsedIconURL: parsedIconURL, eTag: eTag, lastModified: lastModified)
                }
                if activeTasks < maxConcurrentFetches {
                    enqueueNext()
                }
            }
        }
        
        lastRefreshTime = Date()
        if newItemNotificationsEnabled {
            let newUnreadCount = unreadCount
            if newUnreadCount > previousUnreadCount {
                let addedCount = newUnreadCount - previousUnreadCount
                sendNewItemsNotification(addedCount: addedCount)
            }
        }
        save()
    }
    
    // Network fetching - runs off MainActor for true concurrency
    nonisolated func fetchFeedData(_ feed: Feed) async -> (Feed, [FeedItem], String?, String?, String?, String?)? {
        guard let url = URL(string: feed.url) else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("macbar-rssreader/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = requestTimeout
            if let eTag = feed.eTag, !eTag.isEmpty {
                request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = feed.lastModified, !lastModified.isEmpty {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 304 {
                return (feed, [], nil, nil, httpResponse.value(forHTTPHeaderField: "ETag"), httpResponse.value(forHTTPHeaderField: "Last-Modified"))
            }
            if httpResponse.statusCode >= 400 {
                throw URLError(.badServerResponse)
            }
            let parser = RSSParser(feedId: feed.id)
            let newItems = parser.parse(data: data)
            return (feed, newItems, parser.feedTitle, parser.feedIconURL, httpResponse.value(forHTTPHeaderField: "ETag"), httpResponse.value(forHTTPHeaderField: "Last-Modified"))
        } catch {
            return nil
        }
    }
    
    // Process results on MainActor
    private func processFetchedFeed(_ feed: Feed, items newItems: [FeedItem], parsedTitle: String?, parsedIconURL: String?, eTag: String?, lastModified: String?) {
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
            if let eTag = eTag, !eTag.isEmpty {
                feeds[index].eTag = eTag
            }
            if let lastModified = lastModified, !lastModified.isEmpty {
                feeds[index].lastModified = lastModified
            }
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
            processFetchedFeed(result.0, items: result.1, parsedTitle: result.2, parsedIconURL: result.3, eTag: result.4, lastModified: result.5)
            save()
        } else {
            showError(String(format: String(localized: "Failed to fetch %@", bundle: .module), feed.title))
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
        logger.error("\(message, privacy: .public)")
        errorMessage = message
        showingError = true
    }

    private func sendNewItemsNotification(addedCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                Task { @MainActor in
                    self.postNewItemsNotification(addedCount: addedCount)
                }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    Task { @MainActor in
                        self.postNewItemsNotification(addedCount: addedCount)
                    }
                }
            default:
                break
            }
        }
    }

    private func postNewItemsNotification(addedCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "New items available", bundle: .module)
        content.body = String(format: String(localized: "%lld new items", bundle: .module), addedCount)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "rssreader.newitems.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
                    case .notify:
                        result.shouldNotify = true
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
    
    /// Apply auto-actions (star, mark read, notify) for new items - call explicitly after fetch
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
                if rule.action == .notify {
                    sendNotification(for: item, ruleName: rule.name)
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
