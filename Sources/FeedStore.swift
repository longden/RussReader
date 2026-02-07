import SwiftUI
import AppKit
import OSLog
@preconcurrency import UserNotifications
import CoreFoundation

// MARK: - Notification Delegate

/// Handles notification display when app is in foreground and notification click-through
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var feedStore: FeedStore?
    
    /// Show notifications even when app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    /// Handle notification click and custom actions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "OPEN_ARTICLE":
            if let link = userInfo["itemLink"] as? String,
               let url = URL(string: link),
               (url.scheme == "http" || url.scheme == "https") {
                await MainActor.run {
                    _ = NSWorkspace.shared.open(url)
                }
            }
        case "MARK_READ":
            if let itemIdString = userInfo["itemId"] as? String,
               let itemId = UUID(uuidString: itemIdString) {
                await MainActor.run {
                    if let item = feedStore?.items.first(where: { $0.id == itemId }) {
                        feedStore?.markAsRead(item)
                    }
                }
            }
        case "MARK_ALL_READ":
            await MainActor.run {
                feedStore?.markAllAsRead()
            }
        case UNNotificationDefaultActionIdentifier:
            // Default tap — open the article
            if let link = userInfo["itemLink"] as? String,
               let url = URL(string: link),
               (url.scheme == "http" || url.scheme == "https") {
                await MainActor.run {
                    _ = NSWorkspace.shared.open(url)
                }
            }
        default:
            break
        }
    }
}

// MARK: - Feed Store

@MainActor
final class FeedStore: ObservableObject {
    @Published var feeds: [Feed] = []
    @Published var items: [FeedItem] = [] {
        didSet { invalidateDerivedState() }
    }
    @Published var filter: FeedFilter = .all {
        didSet { _cachedFilteredItems = nil }
    }
    @Published var isRefreshing: Bool = false
    @Published var lastRefreshTime: Date?
    @Published var errorMessage: String?
    @Published var showingError: Bool = false
    @Published var filterRules: [FilterRule] = []
    @Published var selectedFeedId: UUID? {
        didSet { _cachedFilteredItems = nil }
    }
    
    @AppStorage("rssHideReadItems") var hideReadItems: Bool = false {
        didSet { _cachedFilteredItems = nil }
    }
    @AppStorage("rssRefreshInterval") var refreshIntervalMinutes: Int = 30
    @AppStorage("rssMaxItemsPerFeed") var maxItemsPerFeed: Int = 25
    @AppStorage("rssFontSize") var fontSize: Double = 13
    @AppStorage("rssTitleMaxLines") var titleMaxLines: Int = 2
    @AppStorage("rssTimeFormat") var timeFormat: String = "12h"
    @AppStorage("rssAppearanceMode") var appearanceMode: String = "system"
    @AppStorage("rssShowUnreadBadge") var showUnreadBadge: Bool = true
    @AppStorage("rssSmartFiltersEnabled") var smartFiltersEnabled: Bool = true {
        didSet { _cachedFilteredItems = nil }
    }
    @AppStorage("rssSelectedBrowser") var selectedBrowser: String = "default"
    @AppStorage("rssShowSummary") var showSummaryGlobal: Bool = false
    @AppStorage("rssLanguage") var selectedLanguage: String = "system"
    @AppStorage("rssStickyWindow") var stickyWindow: Bool = true
    @AppStorage("rssNewItemNotifications") var newItemNotificationsEnabled: Bool = false
    @AppStorage("rssShowFeedIcons") var showFeedIcons: Bool = false
    @AppStorage("rssWindowWidthSize") var windowWidthSize: String = "medium"
    @AppStorage("rssWindowHeightSize") var windowHeightSize: String = "medium"
    
    /// Computed window width based on size preset
    var windowWidth: CGFloat {
        switch windowWidthSize {
        case "small": return 320
        case "large": return 440
        case "xlarge": return 520
        default: return 380  // medium
        }
    }
    
    /// Computed window height based on size preset
    var windowHeight: CGFloat {
        switch windowHeightSize {
        case "small": return 420
        case "large": return 620
        case "xlarge": return 740
        default: return 520  // medium
        }
    }
    
    private let feedsKey = "rssFeeds"
    private let itemsKey = "rssItems"
    private let filterRulesKey = "rssFilterRules"
    private let readKeysKey = "rssReadItemKeys"
    private var refreshTimer: DispatchSourceTimer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.macbar", category: "RSSReader")
    private var saveWorkItem: DispatchWorkItem?
    private let maxTotalItems = 200
    private let itemRetentionDays = 30
    private let requestTimeout: TimeInterval = 15
    
    // Cache for filter results (per-item metadata like highlight color)
    private var filterResultsCache: [UUID: FilteredItemResult] = [:]
    
    // Persistent set of item keys that have been read, survives item trimming
    private var readItemKeys: Set<String> = []
    
    // Cached derived state - invalidated when items change
    private var _cachedFilteredItems: [FeedItem]?
    private var _cachedHiddenCount: Int?
    private var _cachedUnreadCount: Int?
    private var _cachedStarredCount: Int?
    private var _itemIndex: [UUID: Int]?
    
    /// O(1) item lookup by ID
    private func itemIndexMap() -> [UUID: Int] {
        if let cached = _itemIndex { return cached }
        var index = [UUID: Int](minimumCapacity: items.count)
        for (i, item) in items.enumerated() {
            index[item.id] = i
        }
        _itemIndex = index
        return index
    }
    
    private func invalidateDerivedState() {
        _cachedFilteredItems = nil
        _cachedHiddenCount = nil
        _cachedUnreadCount = nil
        _cachedStarredCount = nil
        _itemIndex = nil
    }
    
    var filteredItems: [FeedItem] {
        if let cached = _cachedFilteredItems { return cached }
        
        var result = items
        var hiddenCount = 0
        
        // Filter by selected feed
        if let feedId = selectedFeedId {
            result = result.filter { $0.feedId == feedId }
        }
        
        // Apply smart filters first (without side effects)
        if smartFiltersEnabled && !filterRules.isEmpty {
            let filterResults = computeFilterResults(for: result)
            let visible = filterResults.filter { $0.isVisible }
            hiddenCount = filterResults.count - visible.count
            result = visible.map { $0.item }
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
        
        _cachedFilteredItems = result
        _cachedHiddenCount = hiddenCount
        return result
    }
    
    var hiddenItemCount: Int {
        if let cached = _cachedHiddenCount { return cached }
        // Force filteredItems computation which also caches hiddenCount
        _ = filteredItems
        return _cachedHiddenCount ?? 0
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
        if let cached = _cachedUnreadCount { return cached }
        let count = items.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
        _cachedUnreadCount = count
        return count
    }
    
    var starredCount: Int {
        if let cached = _cachedStarredCount { return cached }
        let count = items.reduce(0) { $0 + ($1.isStarred ? 1 : 0) }
        _cachedStarredCount = count
        return count
    }
    
    init() {
        load()
        loadFilterRules()
        
        // Purge old items only on app startup, not during refresh
        // This prevents deleting items the user just read
        purgeOldItems()
        
        startRefreshTimer()
        setupNotifications()
        
        if feeds.isEmpty {
            addDefaultFeeds()
        }
    }
    
    /// Call this after app is fully initialized to request notification permissions
    func setupNotifications() {
        // Guard against environments without proper app bundle (e.g., swift run)
        guard Bundle.main.bundleIdentifier != nil else {
            logger.info("Skipping notification setup - no bundle identifier (likely swift run)")
            return
        }
        
        // Set delegate and give it a reference to this store for handling actions
        let delegate = NotificationDelegate.shared
        delegate.feedStore = self
        UNUserNotificationCenter.current().delegate = delegate
        
        // Register notification categories with actions
        let openAction = UNNotificationAction(identifier: "OPEN_ARTICLE", title: String(localized: "Open", bundle: .module), options: [.foreground])
        let markReadAction = UNNotificationAction(identifier: "MARK_READ", title: String(localized: "Mark as Read", bundle: .module), options: [])
        let markAllReadAction = UNNotificationAction(identifier: "MARK_ALL_READ", title: String(localized: "Mark All as Read", bundle: .module), options: [])
        
        let singleItemCategory = UNNotificationCategory(identifier: "SINGLE_NEW_ITEM", actions: [openAction, markReadAction], intentIdentifiers: [])
        let multiItemCategory = UNNotificationCategory(identifier: "MULTI_NEW_ITEMS", actions: [markAllReadAction], intentIdentifiers: [])
        
        UNUserNotificationCenter.current().setNotificationCategories([singleItemCategory, multiItemCategory])
        
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
            if var decoded = try? JSONDecoder().decode([FeedItem].self, from: itemsData) {
                // Trim oversized descriptions from previously stored items
                for i in decoded.indices where decoded[i].description.count > 500 {
                    decoded[i].description = String(decoded[i].description.prefix(500))
                }
                items = decoded
            } else {
                logger.error("Failed to decode items from UserDefaults")
                showError(String(localized: "Failed to load items. Your saved data may be corrupted.", bundle: .module))
            }
        }
        
        // Load persistent read keys and rebuild from current read items
        if let saved = UserDefaults.standard.array(forKey: readKeysKey) as? [String] {
            readItemKeys = Set(saved)
        }
        for item in items where item.isRead {
            readItemKeys.insert(itemKey(item))
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
        // Cap read keys to prevent unbounded growth (keep most recent 2000)
        if readItemKeys.count > 2000 {
            readItemKeys = Set(readItemKeys.prefix(2000))
        }
        UserDefaults.standard.set(Array(readItemKeys), forKey: readKeysKey)
    }
    
    // MARK: - Feed Management
    
    func addFeed(url: String, title: String? = nil, authType: AuthType = .none, username: String? = nil, password: String? = nil, token: String? = nil) async -> (success: Bool, errorMessage: String?) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return (false, String(localized: "Feed URL cannot be empty.", bundle: .module)) }
        
        if feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            return (false, String(localized: "This feed is already added.", bundle: .module))
        }
        
        // Validate the feed by attempting to fetch it first
        let tempFeed = Feed(title: title ?? cleanURL, url: cleanURL, customTitle: title != nil, authType: authType)
        
        // Save credentials to Keychain before fetch so fetchFeedData can use them
        if authType == .basicAuth, let username = username, let password = password {
            KeychainHelper.saveBasicAuth(feedId: tempFeed.id, username: username, password: password)
        } else if authType == .bearerToken, let token = token {
            KeychainHelper.saveToken(feedId: tempFeed.id, token: token)
        }
        guard let result = await fetchFeedData(tempFeed) else {
            KeychainHelper.deleteCredentials(feedId: tempFeed.id)
            return (false, String(localized: "Unable to fetch feed. Please check the URL and try again.", bundle: .module))
        }
        
        let (_, fetchedItems, parsedTitle, parsedIconURL, eTag, lastModified) = result
        
        // Ensure we got at least some items
        guard !fetchedItems.isEmpty else {
            KeychainHelper.deleteCredentials(feedId: tempFeed.id)
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
        KeychainHelper.deleteCredentials(feedId: feed.id)
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
        let index = itemIndexMap()
        guard let idx = index[item.id] else { return }
        var updatedItem = items[idx]
        updatedItem.isRead = true
        items[idx] = updatedItem
        readItemKeys.insert(itemKey(updatedItem))
        objectWillChange.send()
        saveImmediately()
    }
    
    func markAsUnread(_ item: FeedItem) {
        let index = itemIndexMap()
        guard let idx = index[item.id] else { return }
        var updatedItem = items[idx]
        updatedItem.isRead = false
        items[idx] = updatedItem
        readItemKeys.remove(itemKey(updatedItem))
        objectWillChange.send()
        saveImmediately()
    }
    
    func toggleStarred(_ item: FeedItem) {
        let index = itemIndexMap()
        guard let idx = index[item.id] else { return }
        var updatedItem = items[idx]
        updatedItem.isStarred.toggle()
        items[idx] = updatedItem
        objectWillChange.send()
        saveImmediately()
    }
    
    func toggleRead(_ item: FeedItem) {
        let index = itemIndexMap()
        guard let idx = index[item.id] else { return }
        var updatedItem = items[idx]
        updatedItem.isRead.toggle()
        items[idx] = updatedItem
        if updatedItem.isRead {
            readItemKeys.insert(itemKey(updatedItem))
        } else {
            readItemKeys.remove(itemKey(updatedItem))
        }
        objectWillChange.send()
        saveImmediately()
    }
    
    func markAllAsRead() {
        items = items.map { item in
            var updated = item
            updated.isRead = true
            readItemKeys.insert(itemKey(updated))
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
            readItemKeys.insert(itemKey(updated))
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
            readItemKeys.insert(itemKey(updated))
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
                // Find the most recent unread item for single-item notifications
                let latestNewItem = items.filter { !$0.isRead }.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }.first
                await sendNewItemsNotification(addedCount: addedCount, latestItem: latestNewItem)
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
            
            // Add authentication headers
            switch feed.authType {
            case .basicAuth:
                if let creds = KeychainHelper.loadBasicAuth(feedId: feed.id) {
                    let credString = "\(creds.username):\(creds.password)"
                    if let credData = credString.data(using: .utf8) {
                        request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
                    }
                }
            case .bearerToken:
                if let creds = KeychainHelper.loadToken(feedId: feed.id) {
                    request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
                }
            case .none:
                break
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 304 {
                return (feed, [], nil, nil, httpResponse.value(forHTTPHeaderField: "ETag"), httpResponse.value(forHTTPHeaderField: "Last-Modified"))
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw URLError(.userAuthenticationRequired)
            }
            if httpResponse.statusCode >= 400 {
                throw URLError(.badServerResponse)
            }
            let parser = RSSParser(feedId: feed.id)
            let newItems = parser.parse(data: data)
            return (feed, newItems, parser.feedTitle, parser.feedIconURL, httpResponse.value(forHTTPHeaderField: "ETag"), httpResponse.value(forHTTPHeaderField: "Last-Modified"))
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            await MainActor.run {
                showError(String(format: String(localized: "Authentication failed for %@. Check your credentials.", bundle: .module), feed.title))
            }
            return nil
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
                var itemToAdd = newItem
                // If this item was previously read (but trimmed), mark it as read
                if readItemKeys.contains(key) {
                    itemToAdd.isRead = true
                }
                items.append(itemToAdd)
                if !itemToAdd.isRead {
                    actuallyNewItems.append(itemToAdd)
                }
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
        
        cleanupFilterCache()
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
            let escapedTitle = feed.title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let escapedURL = feed.url
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
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

    private func sendNewItemsNotification(addedCount: Int, latestItem: FeedItem?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized:
            postNewItemsNotification(addedCount: addedCount, latestItem: latestItem)
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if granted {
                    postNewItemsNotification(addedCount: addedCount, latestItem: latestItem)
                }
            } catch {}
        default:
            break
        }
    }

    private func postNewItemsNotification(addedCount: Int, latestItem: FeedItem?) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        if addedCount == 1, let item = latestItem {
            // Single item: show item title with Open + Mark as Read actions
            content.title = feedTitle(for: item)
            content.body = item.title
            content.userInfo = [
                "itemLink": item.link,
                "itemId": item.id.uuidString
            ]
            content.categoryIdentifier = "SINGLE_NEW_ITEM"
        } else {
            // Multiple items: show count with Mark All as Read action
            content.title = String(localized: "New items available", bundle: .module)
            content.body = String(format: String(localized: "%lld new items", bundle: .module), addedCount)
            content.categoryIdentifier = "MULTI_NEW_ITEMS"
        }

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
        _cachedFilteredItems = nil
        _cachedHiddenCount = nil
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
        
        let index = itemIndexMap()
        var needsSave = false
        
        for item in newItems {
            for rule in enabledRules {
                if !ruleAppliesTo(rule, item: item) { continue }
                guard evaluateRule(rule, for: item) else { continue }
                
                if rule.action == .autoStar && !item.isStarred {
                    if let idx = index[item.id] {
                        var updatedItem = items[idx]
                        updatedItem.isStarred = true
                        items[idx] = updatedItem
                        needsSave = true
                    }
                }
                if rule.action == .markRead && !item.isRead {
                    if let idx = index[item.id] {
                        var updatedItem = items[idx]
                        updatedItem.isRead = true
                        items[idx] = updatedItem
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
