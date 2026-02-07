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
        feedTitle = rssFeed.channel?.title.map { decodeHTMLEntities($0) }
        feedIconURL = rssFeed.channel?.image?.url ?? rssFeed.channel?.iTunes?.image?.attributes?.href
        
        guard let items = rssFeed.channel?.items else { return [] }
        
        return items.compactMap { item -> FeedItem? in
            let title = decodeHTMLEntities(item.title ?? "Untitled")
            let link = decodeHTMLEntities(item.link ?? item.guid?.text ?? "")
            
            guard !link.isEmpty else { return nil }
            
            // Parse enclosures (RSS media)
            let enclosures: [Enclosure] = {
                if let enc = item.enclosure?.attributes {
                    return [Enclosure(
                        url: enc.url ?? "",
                        type: enc.type,
                        length: enc.length.map { Int($0) }
                    )]
                }
                return []
            }()
            
            let rawHTML = item.content?.encoded ?? item.description
            
            return FeedItem(
                feedId: feedId,
                title: title,
                link: link,
                sourceId: item.guid?.text,
                description: stripHTML(item.description ?? ""),
                contentHTML: capHTML(rawHTML),
                pubDate: item.pubDate,
                author: item.author ?? item.dublinCore?.creator,
                categories: item.categories?.compactMap { $0.text } ?? [],
                enclosures: enclosures
            )
        }
    }
    
    private func parseAtomFeed(_ atomFeed: FeedKit.AtomFeed) -> [FeedItem] {
        feedTitle = atomFeed.title?.text.map { decodeHTMLEntities($0) }
        feedIconURL = atomFeed.logo ?? atomFeed.icon
        
        guard let entries = atomFeed.entries else { return [] }
        
        return entries.compactMap { entry -> FeedItem? in
            let title = decodeHTMLEntities(entry.title ?? "Untitled")
            
            let link = entry.links?.first(where: { 
                $0.attributes?.rel == "alternate" || $0.attributes?.type == "text/html" 
            })?.attributes?.href ?? entry.links?.first?.attributes?.href ?? entry.id ?? ""
            
            guard !link.isEmpty else { return nil }
            
            // Parse enclosures from links with rel="enclosure"
            let enclosures: [Enclosure] = entry.links?.compactMap { link in
                guard link.attributes?.rel == "enclosure",
                      let href = link.attributes?.href else { return nil }
                return Enclosure(
                    url: href,
                    type: link.attributes?.type,
                    length: link.attributes?.length.flatMap { Int($0) }
                )
            } ?? []
            
            let rawHTML = entry.content?.text ?? entry.summary?.text
            
            return FeedItem(
                feedId: feedId,
                title: title,
                link: link,
                sourceId: entry.id,
                description: stripHTML(rawHTML ?? ""),
                contentHTML: capHTML(rawHTML),
                pubDate: entry.published ?? entry.updated,
                author: entry.authors?.first?.name,
                categories: entry.categories?.compactMap { $0.attributes?.term } ?? [],
                enclosures: enclosures
            )
        }
    }
    
    private func parseJSONFeed(_ jsonFeed: FeedKit.JSONFeed) -> [FeedItem] {
        feedTitle = jsonFeed.title.map { decodeHTMLEntities($0) }
        feedIconURL = jsonFeed.icon ?? jsonFeed.favicon
        
        guard let items = jsonFeed.items else { return [] }
        
        return items.compactMap { item -> FeedItem? in
            let title = decodeHTMLEntities(item.title ?? "Untitled")
            let link = decodeHTMLEntities(item.url ?? item.externalURL ?? item.id ?? "")
            
            guard !link.isEmpty else { return nil }
            
            // Parse attachments (JSON Feed enclosures)
            let enclosures: [Enclosure] = item.attachments?.compactMap { attachment in
                guard let url = attachment.url else { return nil }
                return Enclosure(
                    url: url,
                    type: attachment.mimeType,
                    length: attachment.sizeInBytes.flatMap { Int($0) }
                )
            } ?? []
            
            let rawHTML = item.contentHtml ?? item.summary
            
            return FeedItem(
                feedId: feedId,
                title: title,
                link: link,
                sourceId: item.id,
                description: stripHTML(item.contentText ?? rawHTML ?? ""),
                contentHTML: capHTML(rawHTML),
                pubDate: item.datePublished,
                author: item.author?.name,
                categories: item.tags ?? [],
                enclosures: enclosures
            )
        }
    }
    
    /// Cap HTML content to prevent excessive memory usage (100KB limit)
    private func capHTML(_ html: String?) -> String? {
        guard let html = html, !html.isEmpty else { return nil }
        if html.count > 100_000 { return String(html.prefix(100_000)) }
        return html
    }
    
    private func stripHTML(_ string: String) -> String {
        guard !string.isEmpty else { return string }
        // Truncate input before expensive regex operations to save CPU and memory
        let input = string.count > 10000 ? String(string.prefix(10000)) : string
        // Fast regex-based HTML stripping (avoids expensive NSAttributedString HTML parser)
        let stripped = input
            .replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<wbr\\s*/?>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<wbr>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = decodeHTMLEntities(stripped)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap output — preserve full content for preview pane, list view handles its own truncation
        if decoded.count > 5000 {
            return String(decoded.prefix(5000))
        }
        return decoded
    }
    
    /// Decode HTML named and numeric entities to their character equivalents
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        // Named entities (most common ones found in RSS feeds)
        let namedEntities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&nbsp;": " ", "&raquo;": "»", "&laquo;": "«",
            "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
            "&bull;": "•", "&middot;": "·", "&copy;": "©", "&reg;": "®", "&trade;": "™",
            "&eacute;": "é", "&egrave;": "è", "&uuml;": "ü", "&ouml;": "ö", "&auml;": "ä",
            "&ntilde;": "ñ", "&ccedil;": "ç",
        ]
        for (entity, char) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric decimal entities: &#NNN;
        while let match = result.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let numStr = result[match].dropFirst(2).dropLast()
            if let code = UInt32(numStr), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(match, with: String(Character(scalar)))
            } else {
                break
            }
        }
        // Numeric hex entities: &#xHHH;
        while let match = result.range(of: #"&#x([0-9a-fA-F]+);"#, options: .regularExpression) {
            let hexStr = result[match].dropFirst(3).dropLast()
            if let code = UInt32(hexStr, radix: 16), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(match, with: String(Character(scalar)))
            } else {
                break
            }
        }
        return result
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
