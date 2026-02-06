import Foundation
import SwiftUI

// MARK: - Feed Filter State

enum FeedFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case starred = "Starred"
    
    var localizedName: String {
        switch self {
        case .all: return String(localized: "All", bundle: .module)
        case .unread: return String(localized: "Unread", bundle: .module)
        case .starred: return String(localized: "Starred", bundle: .module)
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .unread: return "circle.fill"
        case .starred: return "star.fill"
        }
    }
}

// MARK: - Smart Filter Models

struct FilterRule: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var action: FilterAction
    var conditions: [FilterCondition]
    var logic: FilterLogic
    var highlightColor: HighlightColor
    var customColorHex: String?
    var iconEmoji: String?
    var feedScope: FeedScope
    
    init(id: UUID = UUID(), name: String = "New Rule", isEnabled: Bool = true, action: FilterAction = .highlight, conditions: [FilterCondition] = [], logic: FilterLogic = .any, highlightColor: HighlightColor = .blue, customColorHex: String? = nil, iconEmoji: String? = nil, feedScope: FeedScope = .allFeeds) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.action = action
        self.conditions = conditions
        self.logic = logic
        self.highlightColor = highlightColor
        self.customColorHex = customColorHex
        self.iconEmoji = iconEmoji
        self.feedScope = feedScope
    }
    
    var effectiveColor: Color {
        if highlightColor == .custom, let hex = customColorHex {
            return Color(hex: hex)
        }
        return highlightColor.color
    }
}

enum FeedScope: Codable, Hashable {
    case allFeeds
    case specificFeeds([UUID])
    
    var isAllFeeds: Bool {
        if case .allFeeds = self { return true }
        return false
    }
    
    var selectedFeedIds: [UUID] {
        if case .specificFeeds(let ids) = self { return ids }
        return []
    }
}

enum FilterAction: String, Codable, CaseIterable {
    case show = "Show Only"
    case hide = "Hide"
    case highlight = "Highlight"
    case addIcon = "Add Icon"
    case addSummary = "Show Summary"
    case autoStar = "Auto-Star"
    case markRead = "Mark Read"
    case notify = "Send Notification"
    
    var localizedName: String {
        switch self {
        case .show: return String(localized: "Show Only", bundle: .module)
        case .hide: return String(localized: "Hide", bundle: .module)
        case .highlight: return String(localized: "Highlight", bundle: .module)
        case .addIcon: return String(localized: "Add Icon", bundle: .module)
        case .addSummary: return String(localized: "Show Summary", bundle: .module)
        case .autoStar: return String(localized: "Auto-Star", bundle: .module)
        case .markRead: return String(localized: "Mark Read", bundle: .module)
        case .notify: return String(localized: "Send Notification", bundle: .module)
        }
    }
    
    var icon: String {
        switch self {
        case .show: return "eye"
        case .hide: return "eye.slash"
        case .highlight: return "highlighter"
        case .addIcon: return "face.smiling"
        case .addSummary: return "text.alignleft"
        case .autoStar: return "star.fill"
        case .markRead: return "checkmark.circle"
        case .notify: return "bell.badge"
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .show: return String(localized: "Only show items that match this rule", bundle: .module)
        case .hide: return String(localized: "Hide items that match this rule", bundle: .module)
        case .highlight: return String(localized: "Add colored background to matching items", bundle: .module)
        case .addIcon: return String(localized: "Show an emoji/icon next to matching items", bundle: .module)
        case .addSummary: return String(localized: "Show 1-line article summary preview", bundle: .module)
        case .autoStar: return String(localized: "Automatically star matching items", bundle: .module)
        case .markRead: return String(localized: "Automatically mark matching items as read", bundle: .module)
        case .notify: return String(localized: "Send notification when new items match this rule", bundle: .module)
        }
    }
}

enum FilterLogic: String, Codable, CaseIterable {
    case all = "All"
    case any = "Any"
    
    var localizedDescription: String {
        switch self {
        case .all: return String(localized: "all conditions", bundle: .module)
        case .any: return String(localized: "any condition", bundle: .module)
        }
    }
}

struct FilterCondition: Codable, Identifiable, Hashable {
    let id: UUID
    var field: FilterField
    var comparison: FilterComparison
    var value: String
    
    init(id: UUID = UUID(), field: FilterField = .title, comparison: FilterComparison = .contains, value: String = "") {
        self.id = id
        self.field = field
        self.comparison = comparison
        self.value = value
    }
}

enum FilterField: String, Codable, CaseIterable {
    case title = "Title"
    case content = "Content"
    case author = "Author"
    case link = "Link"
    case category = "Category"
    
    var localizedName: String {
        switch self {
        case .title: return String(localized: "Title", bundle: .module)
        case .content: return String(localized: "Content", bundle: .module)
        case .author: return String(localized: "Author", bundle: .module)
        case .link: return String(localized: "Link", bundle: .module)
        case .category: return String(localized: "Category", bundle: .module)
        }
    }
    
    var icon: String {
        switch self {
        case .title: return "textformat"
        case .content: return "doc.text"
        case .author: return "person"
        case .link: return "link"
        case .category: return "tag"
        }
    }
}

enum FilterComparison: String, Codable, CaseIterable {
    case contains = "contains"
    case notContains = "does not contain"
    case equals = "equals"
    case startsWith = "starts with"
    case endsWith = "ends with"
    
    var localizedName: String {
        switch self {
        case .contains: return String(localized: "contains", bundle: .module)
        case .notContains: return String(localized: "does not contain", bundle: .module)
        case .equals: return String(localized: "equals", bundle: .module)
        case .startsWith: return String(localized: "starts with", bundle: .module)
        case .endsWith: return String(localized: "ends with", bundle: .module)
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable {
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case teal = "Teal"
    case custom = "Custom"
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .custom: return .gray
        }
    }
    
    static var presetCases: [HighlightColor] {
        allCases.filter { $0 != .custom }
    }
}

// MARK: - Filter Result

struct FilteredItemResult {
    let item: FeedItem
    var isVisible: Bool = true
    var highlightColor: Color?
    var iconEmoji: String?
    var shouldAutoStar: Bool = false
    var shouldMarkRead: Bool = false
    var shouldShowSummary: Bool = false
    var shouldNotify: Bool = false
    var matchedRuleIds: Set<UUID> = []
}

// MARK: - Authentication

enum AuthType: String, Codable, CaseIterable {
    case none = "none"
    case basicAuth = "basicAuth"
    case bearerToken = "bearerToken"
    
    var localizedName: String {
        switch self {
        case .none: return String(localized: "None", bundle: .module)
        case .basicAuth: return String(localized: "Basic Auth", bundle: .module)
        case .bearerToken: return String(localized: "API Key / Token", bundle: .module)
        }
    }
}

// MARK: - Data Models

struct Feed: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: String
    var lastFetched: Date?
    var eTag: String?
    var lastModified: String?
    var iconURL: String?
    var customTitle: Bool
    var authType: AuthType
    
    init(id: UUID = UUID(), title: String, url: String, lastFetched: Date? = nil, eTag: String? = nil, lastModified: String? = nil, iconURL: String? = nil, customTitle: Bool = false, authType: AuthType = .none) {
        self.id = id
        self.title = title
        self.url = url
        self.lastFetched = lastFetched
        self.eTag = eTag
        self.lastModified = lastModified
        self.iconURL = iconURL
        self.customTitle = customTitle
        self.authType = authType
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        lastFetched = try container.decodeIfPresent(Date.self, forKey: .lastFetched)
        eTag = try container.decodeIfPresent(String.self, forKey: .eTag)
        lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        customTitle = try container.decodeIfPresent(Bool.self, forKey: .customTitle) ?? false
        authType = try container.decodeIfPresent(AuthType.self, forKey: .authType) ?? .none
    }
}

struct FeedItem: Codable, Identifiable, Hashable {
    let id: UUID
    var feedId: UUID
    var title: String
    var link: String
    var sourceId: String?
    var description: String
    var pubDate: Date?
    var author: String?
    var categories: [String]
    var isRead: Bool
    var isStarred: Bool
    var enclosures: [Enclosure]
    
    init(id: UUID = UUID(), feedId: UUID, title: String, link: String, sourceId: String? = nil, description: String = "", pubDate: Date? = nil, author: String? = nil, categories: [String] = [], isRead: Bool = false, isStarred: Bool = false, enclosures: [Enclosure] = []) {
        self.id = id
        self.feedId = feedId
        self.title = title
        self.link = link
        self.sourceId = sourceId
        self.description = description
        self.pubDate = pubDate
        self.author = author
        self.categories = categories
        self.isRead = isRead
        self.isStarred = isStarred
        self.enclosures = enclosures
    }
}

// MARK: - Enclosure (for images, audio, video)

struct Enclosure: Codable, Hashable {
    var url: String
    var type: String?
    var length: Int?
    
    var isImage: Bool {
        guard let type = type?.lowercased() else { return false }
        return type.hasPrefix("image/")
    }
    
    var isAudio: Bool {
        guard let type = type?.lowercased() else { return false }
        return type.hasPrefix("audio/")
    }
    
    var isVideo: Bool {
        guard let type = type?.lowercased() else { return false }
        return type.hasPrefix("video/")
    }
}

// MARK: - Suggested Feeds

struct SuggestedFeed: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    
    init(title: String, url: String) {
        self.title = title
        self.url = url
        self.id = url.lowercased()
    }
}

struct SuggestedFeedPack: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let feeds: [SuggestedFeed]
    
    init(title: String, description: String, feeds: [SuggestedFeed]) {
        self.title = title
        self.description = description
        self.feeds = feeds
        self.id = title.lowercased()
    }
}

enum SuggestedFeeds {
    static let packs: [SuggestedFeedPack] = [
        SuggestedFeedPack(
            title: "AI Essentials",
            description: "Official blogs and research highlights in AI.",
            feeds: [
                SuggestedFeed(title: "OpenAI News", url: "https://openai.com/news/rss.xml"),
                SuggestedFeed(title: "Google AI Blog", url: "https://blog.google/technology/ai/rss/"),
                SuggestedFeed(title: "Microsoft AI Blog", url: "https://blogs.microsoft.com/ai/feed/"),
                SuggestedFeed(title: "MIT AI News", url: "https://news.mit.edu/rss"),
                SuggestedFeed(title: "arXiv cs.AI", url: "https://rss.arxiv.org/rss/cs.AI")
            ]
        ),
        SuggestedFeedPack(
            title: "React Updates",
            description: "React core news plus leading community voices.",
            feeds: [
                SuggestedFeed(title: "React Blog", url: "https://react.dev/rss.xml"),
                SuggestedFeed(title: "React Native Blog", url: "https://reactnative.dev/blog/rss.xml"),
                SuggestedFeed(title: "Overreacted", url: "https://overreacted.io/rss.xml"),
                SuggestedFeed(title: "Josh W. Comeau", url: "https://www.joshwcomeau.com/rss.xml"),
                SuggestedFeed(title: "React Status", url: "https://react.statuscode.com/rss")
            ]
        ),
        SuggestedFeedPack(
            title: "Startup Scene",
            description: "Funding news, founder advice, and product launches.",
            feeds: [
                SuggestedFeed(title: "TechCrunch Startups", url: "https://techcrunch.com/category/startups/feed/"),
                SuggestedFeed(title: "EU-Startups", url: "https://www.eu-startups.com/feed/"),
                SuggestedFeed(title: "StartupNation", url: "https://startupnation.com/feed/"),
                SuggestedFeed(title: "Product Hunt", url: "https://www.producthunt.com/feed"),
                SuggestedFeed(title: "First Round Review", url: "https://firstround.com/review/")
            ]
        ),
        SuggestedFeedPack(
            title: "Cybersecurity",
            description: "Threat intel, security news, and research.",
            feeds: [
                SuggestedFeed(title: "The Hacker News", url: "https://feeds.feedburner.com/TheHack"),
                SuggestedFeed(title: "Krebs on Security", url: "https://krebsonsecurity.com/feed/"),
                SuggestedFeed(title: "Dark Reading", url: "https://www.darkreading.com/rss.xml"),
                SuggestedFeed(title: "BleepingComputer", url: "https://www.bleepingcomputer.com/feed/"),
                SuggestedFeed(title: "SANS Internet Storm Center", url: "https://isc.sans.edu/rssfeed.xml")
            ]
        ),
        SuggestedFeedPack(
            title: "iOS / macOS",
            description: "Swift, Apple dev, and platform news.",
            feeds: [
                SuggestedFeed(title: "Swift by Sundell", url: "https://www.swiftbysundell.com/rss"),
                SuggestedFeed(title: "iOS Dev Weekly", url: "https://iosdevweekly.com/issues.rss"),
                SuggestedFeed(title: "SwiftLee", url: "https://www.avanderlee.com/feed/"),
                SuggestedFeed(title: "Hacking with Swift", url: "https://www.hackingwithswift.com/articles/rss"),
                SuggestedFeed(title: "MacRumors", url: "https://feeds.macrumors.com/MacRumors-All")
            ]
        ),
        SuggestedFeedPack(
            title: "Product Management",
            description: "Discovery, strategy, and product leadership.",
            feeds: [
                SuggestedFeed(title: "Product Talk", url: "https://producttalk.org/feed/"),
                SuggestedFeed(title: "Mind the Product", url: "https://www.mindtheproduct.com/feed/"),
                SuggestedFeed(title: "Roman Pichler", url: "https://www.romanpichler.com/feed/"),
                SuggestedFeed(title: "Product Coalition", url: "https://productcoalition.com/feed"),
                SuggestedFeed(title: "Sachin Rekhi", url: "https://sachinrekhi.com/feed/")
            ]
        ),
        SuggestedFeedPack(
            title: "Machine Learning",
            description: "ML research, tutorials, and industry trends.",
            feeds: [
                SuggestedFeed(title: "Towards Data Science", url: "https://towardsdatascience.com/feed"),
                SuggestedFeed(title: "Machine Learning Mastery", url: "https://machinelearningmastery.com/blog/feed"),
                SuggestedFeed(title: "KDnuggets", url: "https://www.kdnuggets.com/feed"),
                SuggestedFeed(title: "arXiv cs.LG", url: "https://arxiv.org/rss/cs.LG"),
                SuggestedFeed(title: "BAIR Blog", url: "https://bair.berkeley.edu/blog/feed.xml")
            ]
        )
    ]
}
