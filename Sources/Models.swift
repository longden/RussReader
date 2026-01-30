import Foundation

// MARK: - Filter State

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

// MARK: - Data Models

struct Feed: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: String
    var lastFetched: Date?
    var iconURL: String?
    
    init(id: UUID = UUID(), title: String, url: String, lastFetched: Date? = nil, iconURL: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.lastFetched = lastFetched
        self.iconURL = iconURL
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
