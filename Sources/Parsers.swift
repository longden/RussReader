import Foundation
import AppKit

// MARK: - RSS Parser

final class RSSParser: NSObject, XMLParserDelegate {
    private let feedId: UUID
    private var items: [FeedItem] = []
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentPublished: String = ""
    private var currentUpdated: String = ""
    private var currentAuthor: String = ""
    private var currentEntryId: String = ""
    private var currentGuid: String = ""
    private var isInItem: Bool = false
    private var isInChannel: Bool = false
    var feedTitle: String?
    
    private static let dateCache = NSCache<NSString, NSDate>()
    
    init(feedId: UUID) {
        self.feedId = feedId
        super.init()
        Self.configureDateCache()
    }
    
    private static func configureDateCache() {
        dateCache.countLimit = 500
    }
    
    func parse(data: Data) -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        let result = items
        items.removeAll()
        return result
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        
        if elementName == "channel" || elementName == "feed" {
            isInChannel = true
        }
        
        if elementName == "item" || elementName == "entry" {
            // If we're already in an item and encounter another item tag,
            // finalize the current one first (handles malformed feeds)
            if isInItem && (!currentTitle.isEmpty || !currentLink.isEmpty) {
                finalizeCurrentItem()
            }
            
            isInItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
            currentPublished = ""
            currentUpdated = ""
            currentAuthor = ""
            currentEntryId = ""
            currentGuid = ""
        }
        
        // Handle Atom link elements
        if elementName == "link" && isInItem {
            if let href = attributeDict["href"] {
                let rel = (attributeDict["rel"] ?? "").lowercased()
                let type = (attributeDict["type"] ?? "").lowercased()
                if rel.isEmpty || rel == "alternate" || type == "text/html" {
                    currentLink = href
                }
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if isInItem {
            switch currentElement {
            case "title":
                currentTitle += trimmed
            case "link":
                currentLink += trimmed
            case "description", "summary", "content":
                currentDescription += trimmed
            case "pubDate":
                currentPubDate += trimmed
            case "published":
                currentPublished += trimmed
            case "updated":
                currentUpdated += trimmed
            case "author", "dc:creator":
                currentAuthor += trimmed
            case "id":
                currentEntryId += trimmed
            case "guid":
                currentGuid += trimmed
            default:
                break
            }
        } else if isInChannel && currentElement == "title" && feedTitle == nil {
            feedTitle = trimmed
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" || elementName == "entry" {
            finalizeCurrentItem()
            isInItem = false
        }
        
        if elementName == "channel" || elementName == "feed" {
            isInChannel = false
        }
    }
    
    private func finalizeCurrentItem() {
        guard !currentTitle.isEmpty || !currentLink.isEmpty else { return }
        
        let sourceId = currentGuid.isEmpty ? currentEntryId : currentGuid
        let resolvedLink = currentLink.isEmpty ? sourceId : currentLink
        let dateString = !currentPubDate.isEmpty ? currentPubDate : (!currentPublished.isEmpty ? currentPublished : currentUpdated)
        let item = FeedItem(
            feedId: feedId,
            title: currentTitle.isEmpty ? "Untitled" : currentTitle,
            link: resolvedLink,
            sourceId: sourceId.isEmpty ? nil : sourceId,
            description: stripHTML(currentDescription),
            pubDate: parseDate(dateString),
            author: currentAuthor.isEmpty ? nil : currentAuthor
        )
        items.append(item)
    }
    
    private func stripHTML(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return string }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
    
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private static let iso8601FormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private static let dateFormatters: [DateFormatter] = {
        let rfc822 = DateFormatter()
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        
        let rfc822Short = DateFormatter()
        rfc822Short.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        rfc822Short.locale = Locale(identifier: "en_US_POSIX")
        
        let iso8601 = DateFormatter()
        iso8601.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        iso8601.locale = Locale(identifier: "en_US_POSIX")
        
        let iso8601Full = DateFormatter()
        iso8601Full.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        iso8601Full.locale = Locale(identifier: "en_US_POSIX")
        
        return [rfc822, rfc822Short, iso8601, iso8601Full]
    }()
    
    private func parseDate(_ string: String) -> Date? {
        let cacheKey = string as NSString
        if let cached = Self.dateCache.object(forKey: cacheKey) {
            return cached as Date
        }
        
        var parsedDate: Date?
        if let iso = Self.iso8601Formatter.date(from: string) {
            parsedDate = iso
        } else if let iso = Self.iso8601FormatterNoFraction.date(from: string) {
            parsedDate = iso
        } else {
            for formatter in Self.dateFormatters {
                if let date = formatter.date(from: string) {
                    parsedDate = date
                    break
                }
            }
        }
        
        if let date = parsedDate {
            Self.dateCache.setObject(date as NSDate, forKey: cacheKey)
        }
        
        return parsedDate
    }
}

// MARK: - OPML Parser

final class OPMLParser: NSObject, XMLParserDelegate {
    private var feeds: [Feed] = []
    
    func parse(data: Data) -> [Feed] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return feeds
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "outline" {
            if let xmlUrl = attributeDict["xmlUrl"], !xmlUrl.isEmpty {
                let title = attributeDict["title"] ?? attributeDict["text"] ?? xmlUrl
                let feed = Feed(title: title, url: xmlUrl)
                feeds.append(feed)
            }
        }
    }
}
