import Foundation
import SwiftUI

// MARK: - Feed Filter State

enum FeedFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case starred = "Starred"
    
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
    case autoStar = "Auto-Star"
    case markRead = "Mark as Read"
    
    var icon: String {
        switch self {
        case .show: return "eye"
        case .hide: return "eye.slash"
        case .highlight: return "highlighter"
        case .addIcon: return "face.smiling"
        case .autoStar: return "star.fill"
        case .markRead: return "checkmark.circle"
        }
    }
    
    var description: String {
        switch self {
        case .show: return "Only show items that match this rule"
        case .hide: return "Hide items that match this rule"
        case .highlight: return "Add colored background to matching items"
        case .addIcon: return "Show an emoji/icon next to matching items"
        case .autoStar: return "Automatically star matching items"
        case .markRead: return "Automatically mark matching items as read"
        }
    }
}

enum FilterLogic: String, Codable, CaseIterable {
    case all = "All"
    case any = "Any"
    
    var description: String {
        switch self {
        case .all: return "all conditions match"
        case .any: return "any condition matches"
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
    case link = "URL"
    
    var icon: String {
        switch self {
        case .title: return "textformat"
        case .content: return "doc.text"
        case .author: return "person"
        case .link: return "link"
        }
    }
    
    var helpText: String {
        switch self {
        case .title: return "The article headline"
        case .content: return "Article description/summary text"
        case .author: return "The author's name (if available)"
        case .link: return "The article URL"
        }
    }
}

enum FilterComparison: String, Codable, CaseIterable {
    case contains = "contains"
    case notContains = "doesn't contain"
    case equals = "equals"
    case startsWith = "starts with"
    case endsWith = "ends with"
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
    var matchedRuleIds: Set<UUID> = []
}

// MARK: - Data Models

struct Feed: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: String
    var lastFetched: Date?
    var iconURL: String?
    var customTitle: Bool
    
    init(id: UUID = UUID(), title: String, url: String, lastFetched: Date? = nil, iconURL: String? = nil, customTitle: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.lastFetched = lastFetched
        self.iconURL = iconURL
        self.customTitle = customTitle
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
    var isRead: Bool
    var isStarred: Bool
    
    init(id: UUID = UUID(), feedId: UUID, title: String, link: String, sourceId: String? = nil, description: String = "", pubDate: Date? = nil, author: String? = nil, isRead: Bool = false, isStarred: Bool = false) {
        self.id = id
        self.feedId = feedId
        self.title = title
        self.link = link
        self.sourceId = sourceId
        self.description = description
        self.pubDate = pubDate
        self.author = author
        self.isRead = isRead
        self.isStarred = isStarred
    }
}
