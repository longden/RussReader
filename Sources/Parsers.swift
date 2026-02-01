import Foundation
import AppKit
import FeedKit
import OSLog

// MARK: - RSS Parser using FeedKit

final class RSSParser {
    private let feedId: UUID
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.macbar", category: "RSSParser")
    var feedTitle: String?
    var feedIconURL: String?
    
    init(feedId: UUID) {
        self.feedId = feedId
    }
    
    func parse(data: Data) -> [FeedItem] {
        do {
            let parsedFeed = try FeedKit.Feed(data: data)
            
            switch parsedFeed {
            case .rss(let rssFeed):
                return parseRSSFeed(rssFeed)
            case .atom(let atomFeed):
                return parseAtomFeed(atomFeed)
            case .json(let jsonFeed):
                return parseJSONFeed(jsonFeed)
            }
        } catch {
            // FeedKit can fail on malformed feeds - log but don't crash
            logger.warning("Feed parsing failed: \(error.localizedDescription)")
            return []
        }
    }
    
    private func parseRSSFeed(_ rssFeed: FeedKit.RSSFeed) -> [FeedItem] {
        feedTitle = rssFeed.channel?.title
        feedIconURL = rssFeed.channel?.image?.url ?? rssFeed.channel?.iTunes?.image?.attributes?.href
        
        guard let items = rssFeed.channel?.items else { return [] }
        
        return items.compactMap { item -> FeedItem? in
            let title = item.title ?? "Untitled"
            let link = item.link ?? item.guid?.text ?? ""
            
            guard !link.isEmpty else { return nil }
            
            // Parse enclosures (RSS media)
            // Note: FeedKit may use different property names - leaving empty for now
            let enclosures: [Enclosure] = []
            
            return FeedItem(
                feedId: feedId,
                title: title,
                link: link,
                sourceId: item.guid?.text,
                description: stripHTML(item.description ?? ""),
                pubDate: item.pubDate,
                author: item.author ?? item.dublinCore?.creator,
                categories: item.categories?.compactMap { $0.text } ?? [],
                enclosures: enclosures
            )
        }
    }
    
    private func parseAtomFeed(_ atomFeed: FeedKit.AtomFeed) -> [FeedItem] {
        feedTitle = atomFeed.title?.text
        feedIconURL = atomFeed.logo ?? atomFeed.icon
        
        guard let entries = atomFeed.entries else { return [] }
        
        return entries.compactMap { entry -> FeedItem? in
            let title = entry.title ?? "Untitled"
            
            let link = entry.links?.first(where: { 
                $0.attributes?.rel == "alternate" || $0.attributes?.type == "text/html" 
            })?.attributes?.href ?? entry.links?.first?.attributes?.href ?? entry.id ?? ""
            
            guard !link.isEmpty else { return nil }
            
            // Parse enclosures from links with rel="enclosure"
            // Note: FeedKit may use different property names - leaving empty for now
            let enclosures: [Enclosure] = []
            
            return FeedItem(
                feedId: feedId,
                title: title,
                link: link,
                sourceId: entry.id,
                description: stripHTML(entry.summary?.text ?? entry.content?.text ?? ""),
                pubDate: entry.published ?? entry.updated,
                author: entry.authors?.first?.name,
                categories: entry.categories?.compactMap { $0.attributes?.term } ?? [],
                enclosures: enclosures
            )
        }
    }
    
    private func parseJSONFeed(_ jsonFeed: FeedKit.JSONFeed) -> [FeedItem] {
        feedTitle = jsonFeed.title
        feedIconURL = jsonFeed.icon ?? jsonFeed.favicon
        
        guard let items = jsonFeed.items else { return [] }
        
        return items.compactMap { item -> FeedItem? in
            let title = item.title ?? "Untitled"
            let link = item.url ?? item.externalURL ?? item.id ?? ""
            
            guard !link.isEmpty else { return nil }
            
            // Parse attachments (JSON Feed enclosures)
            // Note: FeedKit may use different property names - leaving empty for now  
            let enclosures: [Enclosure] = []
            
            return FeedItem(
                feedId: feedId,
                title: title,
                link: link,
                sourceId: item.id,
                description: stripHTML(item.contentText ?? item.contentHtml ?? item.summary ?? ""),
                pubDate: item.datePublished,
                author: item.author?.name,
                categories: item.tags ?? [],
                enclosures: enclosures
            )
        }
    }
    
    private func stripHTML(_ string: String) -> String {
        guard !string.isEmpty else { return string }
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
