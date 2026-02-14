//
//  ArticlePreviewPane.swift
//  RussReader
//
//  Article detail view with full content preview
//

import SwiftUI
import SwiftSoup
import AppKit

struct ArticlePreviewPane: View {
    let item: FeedItem
    let feedTitle: String
    @ObservedObject var store: FeedStore
    let onClose: () -> Void
    
    @State private var fullContent: String?
    @State private var fullContentHTML: String?
    @State private var isLoadingContent = false
    @State private var contentBlocks: [ContentBlock]?
    @State private var isParsing = true
    @State private var loadFailed = false
    
    /// Live item from store (reflects star/read toggles)
    private var liveItem: FeedItem {
        store.items.first(where: { $0.id == item.id }) ?? item
    }
    
    var body: some View {
        VStack(spacing: 0) {
            previewToolbar
            Divider()
            previewContent
        }
        .task {
            // Parse feed HTML content blocks off main thread
            if let html = item.contentHTML, !html.isEmpty {
                let title = item.title
                let blocks = await Task.detached(priority: .userInitiated) {
                    self.parseContentBlocks(from: html, articleTitle: title)
                }.value
                if !blocks.isEmpty {
                    contentBlocks = blocks
                }
            }
            isParsing = false
            // Auto-fetch full article when feed content produced no blocks
            // (e.g. contentHTML not persisted after restart, or feed only has a summary)
            if (contentBlocks ?? []).isEmpty {
                await loadFullContent()
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ViewBuilder
    private var previewToolbar: some View {
        let buttons = HStack(spacing: 8) {
            toolbarButton(liveItem.isStarred ? "star.fill" : "star", tint: liveItem.isStarred ? .yellow : nil) {
                store.toggleStarred(liveItem)
            }
            toolbarButton(liveItem.isRead ? "envelope.open" : "envelope.badge", tint: nil) {
                store.toggleRead(liveItem)
            }
            toolbarButton("square.and.arrow.up", tint: nil) {
                store.shareItem(liveItem)
            }
            toolbarButton("safari", tint: nil) {
                store.openItem(liveItem)
            }
        }
        
        if #available(macOS 26.0, *) {
            HStack(spacing: 12) {
                Button { onClose() } label: {
                    Label(String(localized: "Back"), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(HeaderButtonHoverModifier())
                .pointerOnHover()
                
                Spacer()
                
                GlassEffectContainer { buttons }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .sectionDivider()
        } else {
            HStack(spacing: 12) {
                Button { onClose() } label: {
                    Label(String(localized: "Back"), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(HeaderButtonHoverModifier())
                .pointerOnHover()
                
                Spacer()
                
                buttons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .sectionDivider()
        }
    }
    
    private func toolbarButton(_ icon: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HeaderButtonHoverModifier())
        .pointerOnHover()
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var previewContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                previewHeader
                Divider()
                previewBody
                previewLoadFullArticleButton
                previewLoadingIndicator
                previewCategories
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
    
    @ViewBuilder
    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 8) {
                Text(feedTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                if let author = item.author, !author.isEmpty {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(author)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                if let pubDate = item.pubDate {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(previewDateString(pubDate))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 4)
    }
    
    @ViewBuilder
    private var previewBody: some View {
        let blocks = contentBlocks ?? []
        
        if loadFailed {
            previewErrorState
        } else if blocks.isEmpty && !isLoadingContent && !isParsing {
            previewEmptyState
        } else {
            previewContentBlocks(blocks)
        }
    }
    
    @ViewBuilder
    private var previewErrorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(String(localized: "Couldn't load article"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button(String(localized: "Open in Browser")) {
                store.openItem(item)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    @ViewBuilder
    private var previewEmptyState: some View {
        let content = fullContent ?? item.description
        if content.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(.quaternary)
                Text(String(localized: "No preview available"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button(String(localized: "Open in Browser")) {
                    store.openItem(item)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            Text(content)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @ViewBuilder
    private func previewContentBlocks(_ blocks: [ContentBlock]) -> some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
            previewContentBlock(block)
        }
    }
    
    @ViewBuilder
    private func previewContentBlock(_ block: ContentBlock) -> some View {
        switch block {
        case .text(let attrText):
            if !attrText.characters.isEmpty {
                Text(attrText)
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
            }
        case .heading(let attrText, let level):
            Text(attrText)
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 8 : 4)
        case .blockquote(let attrText):
            previewBlockquote(attrText)
        case .image(let url, let caption):
            previewImage(url: url, caption: caption)
        case .code(let code):
            previewCodeBlock(code)
        case .divider:
            Divider()
                .padding(.vertical, 4)
        case .list(let items, let ordered):
            previewList(items: items, ordered: ordered)
        case .table(let rows):
            previewTable(rows: rows)
        case .definitionList(let pairs):
            previewDefinitionList(pairs: pairs)
        case .details(let summary, let content):
            previewDetails(summary: summary, content: content)
        }
    }
    
    @ViewBuilder
    private func previewBlockquote(_ attrText: AttributedString) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 3)
            Text(attrText)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .italic()
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func previewImage(url: URL, caption: String?) -> some View {
        VStack(spacing: 4) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure:
                    EmptyView()
                case .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 120)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            
            if let caption = caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func previewCodeBlock(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.8))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private func previewList(items: [AttributedString], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: ordered ? 20 : 10, alignment: .trailing)
                    Text(text)
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    @ViewBuilder
    private func previewTable(rows: [[AttributedString]]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            previewTableGrid(rows: rows)
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private func previewTableGrid(rows: [[AttributedString]]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                previewTableRow(row: row, index: rowIdx)
                if rowIdx == 0 { Divider() }
            }
        }
        .padding(12)
    }
    
    @ViewBuilder
    private func previewTableRow(row: [AttributedString], index: Int) -> some View {
        GridRow {
            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                let weight: Font.Weight = index == 0 ? .semibold : .regular
                let color: Color = index == 0 ? .primary : Color.primary.opacity(0.85)
                Text(cell)
                    .font(.system(size: 13, weight: weight))
                    .foregroundStyle(color)
            }
        }
    }
    
    @ViewBuilder
    private func previewDefinitionList(pairs: [(term: AttributedString, definition: AttributedString)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.term)
                        .font(.system(size: 14, weight: .semibold))
                    Text(pair.definition)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
            }
        }
    }
    
    @ViewBuilder
    private func previewDetails(summary: String, content: [ContentBlock]) -> some View {
        DisclosureGroup(summary) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(content.enumerated()), id: \.offset) { _, innerBlock in
                    switch innerBlock {
                    case .text(let t): 
                        Text(t).font(.system(size: 14)).lineSpacing(5)
                    case .code(let c): 
                        Text(c).font(.system(size: 12, design: .monospaced)).foregroundStyle(.primary.opacity(0.8))
                    default: 
                        EmptyView()
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.system(size: 14, weight: .medium))
    }
    
    @ViewBuilder
    private var previewLoadingIndicator: some View {
        if isLoadingContent {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Loading full article…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var previewLoadFullArticleButton: some View {
        if !isLoadingContent && !(contentBlocks ?? []).isEmpty && fullContentHTML == nil {
            Button {
                Task { await loadFullContent() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 11))
                    Text(String(localized: "Load full article"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .modifier(HeaderButtonHoverModifier())
            .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private var previewCategories: some View {
        if !item.categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(item.categories.prefix(5), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 120, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Date Formatting
    
    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 17
        case 3: return 15
        case 4: return 14
        default: return 13
        }
    }
    
    private static let previewDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    private func previewDateString(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return String(localized: "Just now") }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: String(localized: "%lld min ago"), minutes) }
        let hours = minutes / 60
        if hours < 24 { return String(format: String(localized: "%lld hr ago"), hours) }
        let days = hours / 24
        if days < 7 { return String(format: String(localized: "%lld days ago"), days) }
        return Self.previewDateFormatter.string(from: date)
    }
    
    // MARK: - Content Block Parsing (SwiftSoup)
    
    private enum ContentBlock {
        case text(AttributedString)
        case heading(AttributedString, level: Int)
        case blockquote(AttributedString)
        case image(URL, caption: String?)
        case code(String)
        case divider
        case list([AttributedString], ordered: Bool)
        case table([[AttributedString]])
        case definitionList([(term: AttributedString, definition: AttributedString)])
        case details(summary: String, content: [ContentBlock])
    }
    
    /// Strip HTML tags from preformatted content while preserving whitespace and line breaks
    nonisolated private func stripHTMLPreservingWhitespace(_ html: String) -> String {
        let stripped = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<wbr\\s*/?>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Dedent: remove common leading whitespace (from XML/feed indentation)
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonEmptyLines.count > 1 else { return stripped }
        
        // Skip first line (often has no indent since it follows opening tag directly)
        let indentCandidates = nonEmptyLines.dropFirst()
        let minIndent = indentCandidates.map { line -> Int in
            line.prefix(while: { $0 == " " || $0 == "\t" }).count
        }.min() ?? 0
        
        if minIndent > 0 {
            return lines.map { line in
                let lineIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                let toStrip = min(minIndent, lineIndent)
                return toStrip > 0 ? String(line.dropFirst(toStrip)) : line
            }.joined(separator: "\n")
        }
        return stripped
    }
    
    /// Builds an AttributedString from a SwiftSoup Element, applying inline formatting
    nonisolated private func buildAttributedString(from element: Element) -> AttributedString {
        var result = AttributedString()
        let nodes = element.getChildNodes()
        // Cap node processing to prevent huge articles from hanging
        let cappedNodes = nodes.count > 500 ? Array(nodes.prefix(500)) : Array(nodes)
        for node in cappedNodes {
            if let textNode = node as? TextNode {
                result.append(AttributedString(textNode.text()))
            } else if let child = node as? Element {
                let tag = child.tagName().lowercased()
                if tag == "br" {
                    result.append(AttributedString("\n"))
                    continue
                }
                var childAttr = buildAttributedString(from: child)
                switch tag {
                case "strong", "b":
                    childAttr.inlinePresentationIntent = .stronglyEmphasized
                case "em", "i":
                    childAttr.inlinePresentationIntent = .emphasized
                case "a":
                    if let href = try? child.attr("href"), let url = URL(string: href) {
                        childAttr.link = url
                        childAttr.foregroundColor = .accentColor
                    }
                case "code":
                    childAttr.font = Font.system(size: 13, design: .monospaced)
                    childAttr.backgroundColor = Color.primary.opacity(0.06)
                case "del", "s":
                    childAttr.strikethroughStyle = Text.LineStyle(pattern: .solid, color: nil)
                case "mark":
                    childAttr.backgroundColor = Color.yellow.opacity(0.3)
                case "abbr":
                    childAttr.underlineStyle = Text.LineStyle(pattern: .solid, color: nil)
                default:
                    break
                }
                result.append(childAttr)
            }
        }
        return result
    }

    /// Parses HTML into alternating text and image blocks using SwiftSoup DOM parser
    nonisolated private func parseContentBlocks(from html: String?, articleTitle: String = "") -> [ContentBlock] {
        guard let html = html, !html.isEmpty else { return [] }
        
        let normalizedTitle = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        return autoreleasepool {
            // Cap input to prevent parsing extremely large HTML
            let cappedHTML = html.count > 500_000 ? String(html.prefix(500_000)) : html
            
            guard let doc = try? SwiftSoup.parseBodyFragment(cappedHTML) else {
                return []
            }
            
            // Remove non-content elements
            _ = try? doc.select("script, style, nav, footer, form, button, input, select, textarea, svg, iframe, object, embed, applet, template, noscript, [role=navigation], [role=banner], [role=complementary], [aria-hidden=true], .ad, .advertisement, .social-share, .related-posts, .newsletter-signup, .comments, .breadcrumb, .pagination, .dropdown, .dropdown-menu, .flash, .sr-only, .linkback").remove()
            
            guard let body = doc.body() else { return [] }
            
            // Normalize br-separated content into paragraphs for feeds that don't use <p> tags
            if let bodyHTML = try? body.html() {
                let normalized = bodyHTML
                    .replacingOccurrences(of: "<br\\s*/?>\\s*<br\\s*/?>", with: "</p><p>", options: .regularExpression)
                _ = try? body.html("<p>" + normalized + "</p>")
            }
        
        var blocks: [ContentBlock] = []
        
        // Walk top-level children, grouping into text/image blocks
        for child in body.children() {
            extractBlocks(from: child, into: &blocks)
        }
        
        // If no children were block elements, process the body as a whole
        if blocks.isEmpty, let text = try? body.text(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.text(AttributedString(text)))
        }
        
            // Remove first heading if it duplicates the article title
            if !normalizedTitle.isEmpty, let firstIdx = blocks.firstIndex(where: {
                if case .heading(_, _) = $0 { return true }
                return false
            }) {
                if case .heading(let attrText, _) = blocks[firstIdx],
                   String(attrText.characters).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle {
                    blocks.remove(at: firstIdx)
                }
            }
            
            // Cap total blocks to prevent rendering issues
            if blocks.count > 100 {
                return Array(blocks.prefix(100))
            }
            
            return blocks
        } // autoreleasepool
    }
    
    /// Recursively extracts content blocks from an element
    nonisolated private func extractBlocks(from element: Element, into blocks: inout [ContentBlock], depth: Int = 0) {
        // Guard against deeply nested HTML causing stack overflow
        guard depth < 20 else { return }
        // Cap total blocks to avoid runaway processing
        guard blocks.count < 100 else { return }
        
        let tag = element.tagName().lowercased()
        
        // Skip non-content elements that may have survived earlier removal
        let skipTags: Set<String> = ["script", "style", "nav", "footer", "form", "button", "input", "select", "textarea", "svg", "iframe", "object", "embed", "applet", "template", "noscript", "canvas", "video", "audio"]
        if skipTags.contains(tag) { return }
        
        // Handle images directly
        if tag == "img" {
            if let imageBlock = extractImage(from: element) {
                blocks.append(imageBlock)
            }
            return
        }
        
        // Handle figure — look for img + figcaption
        if tag == "figure" {
            if let img = try? element.select("img").first(),
               let imageBlock = extractImage(from: img, figcaption: try? element.select("figcaption").text()) {
                blocks.append(imageBlock)
            }
            return
        }
        
        // Handle code blocks (<pre> or <pre><code>)
        if tag == "pre" {
            // Use html() and strip tags to preserve whitespace formatting
            if let innerHTML = try? element.html() {
                let codeText = stripHTMLPreservingWhitespace(innerHTML)
                if !codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = codeText.trimmingCharacters(in: .newlines)
                    let cappedCode = trimmed.count > 5000 ? String(trimmed.prefix(5000)) + "\n…" : trimmed
                    blocks.append(.code(cappedCode))
                }
            }
            return
        }
        
        // Handle headings
        if tag.count == 2 && tag.hasPrefix("h"), let level = Int(String(tag.last!)), (1...6).contains(level) {
            let richText = buildAttributedString(from: element)
            if !richText.characters.isEmpty {
                blocks.append(.heading(richText, level: level))
            }
            return
        }
        
        // Handle blockquotes
        if tag == "blockquote" {
            let richText = buildAttributedString(from: element)
            if !richText.characters.isEmpty {
                blocks.append(.blockquote(richText))
            }
            return
        }
        
        // Handle horizontal rules
        if tag == "hr" {
            blocks.append(.divider)
            return
        }
        
        // Handle lists
        if tag == "ul" || tag == "ol" {
            let items = (try? element.select("> li"))?.array().map { buildAttributedString(from: $0) }
                .filter { !$0.characters.isEmpty } ?? []
            if !items.isEmpty {
                blocks.append(.list(items, ordered: tag == "ol"))
            }
            return
        }
        
        // Handle tables
        if tag == "table" {
            var rows: [[AttributedString]] = []
            for row in (try? element.select("tr")) ?? Elements() {
                let cells = (try? row.select("th, td")) ?? Elements()
                let cellTexts = cells.array().map { buildAttributedString(from: $0) }
                if !cellTexts.isEmpty { rows.append(cellTexts) }
            }
            if !rows.isEmpty { blocks.append(.table(rows)) }
            return
        }
        
        // Handle definition lists
        if tag == "dl" {
            var pairs: [(term: AttributedString, definition: AttributedString)] = []
            var currentTerm: AttributedString?
            for child in element.children() {
                let childTag = child.tagName().lowercased()
                if childTag == "dt" {
                    currentTerm = buildAttributedString(from: child)
                } else if childTag == "dd", let term = currentTerm {
                    pairs.append((term: term, definition: buildAttributedString(from: child)))
                    currentTerm = nil
                }
            }
            if !pairs.isEmpty { blocks.append(.definitionList(pairs)) }
            return
        }
        
        // Handle details/summary
        if tag == "details" {
            let summary = (try? element.select("summary").first()?.text()) ?? "Details"
            var innerBlocks: [ContentBlock] = []
            for child in element.children() where child.tagName().lowercased() != "summary" {
                extractBlocks(from: child, into: &innerBlocks, depth: depth + 1)
            }
            if !innerBlocks.isEmpty { blocks.append(.details(summary: summary, content: innerBlocks)) }
            return
        }
        
        // Container elements should be recursed into to find nested blocks
        let isContainer = ["div", "section", "article", "main", "aside", "header"].contains(tag) && element.children().size() > 0
        
        if isContainer {
            // Element has mixed content — process children individually
            for child in element.children() {
                extractBlocks(from: child, into: &blocks, depth: depth + 1)
            }
            // Also get any direct text content not in child elements
            let ownText = element.ownText()
            if !ownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(AttributedString(ownText.trimmingCharacters(in: .whitespacesAndNewlines))))
            }
        } else if (try? element.select("img"))?.isEmpty() == false {
            // Mixed text+image element (e.g. <p> with inline <img>) —
            // split into image blocks and text runs to avoid dropping images
            var textRun = AttributedString()
            for node in element.getChildNodes() {
                if let child = node as? Element {
                    let childTag = child.tagName().lowercased()
                    if childTag == "img" {
                        if !textRun.characters.isEmpty {
                            blocks.append(.text(textRun))
                            textRun = AttributedString()
                        }
                        if let imageBlock = extractImage(from: child) {
                            blocks.append(imageBlock)
                        }
                    } else if childTag == "br" {
                        // skip br separators between content
                    } else {
                        var childAttr = buildAttributedString(from: child)
                        switch childTag {
                        case "strong", "b": childAttr.inlinePresentationIntent = .stronglyEmphasized
                        case "em", "i": childAttr.inlinePresentationIntent = .emphasized
                        case "a":
                            if let href = try? child.attr("href"), let url = URL(string: href) {
                                childAttr.link = url
                                childAttr.foregroundColor = .accentColor
                            }
                        case "code":
                            childAttr.font = Font.system(size: 13, design: .monospaced)
                            childAttr.backgroundColor = Color.primary.opacity(0.06)
                        case "del", "s": childAttr.strikethroughStyle = Text.LineStyle(pattern: .solid, color: nil)
                        case "mark": childAttr.backgroundColor = Color.yellow.opacity(0.3)
                        case "abbr": childAttr.underlineStyle = Text.LineStyle(pattern: .solid, color: nil)
                        default: break
                        }
                        textRun.append(childAttr)
                    }
                } else if let textNode = node as? TextNode {
                    let text = textNode.text()
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        textRun.append(AttributedString(text))
                    }
                }
            }
            if !textRun.characters.isEmpty {
                blocks.append(.text(textRun))
            }
        } else {
            // Pure text element — build rich AttributedString with inline formatting
            let richText = buildAttributedString(from: element)
            if !richText.characters.isEmpty {
                // Merge with previous text block if consecutive
                if case .text(var prev) = blocks.last {
                    prev.append(AttributedString("\n\n"))
                    prev.append(richText)
                    blocks[blocks.count - 1] = .text(prev)
                } else {
                    blocks.append(.text(richText))
                }
            }
        }
    }
    
    /// Extracts an image block from an img element, filtering out tracking pixels
    nonisolated private func extractImage(from element: Element, figcaption: String? = nil) -> ContentBlock? {
        guard var src = try? element.attr("src"), !src.isEmpty else { return nil }
        
        // Handle relative/protocol-relative URLs
        if src.hasPrefix("//") {
            src = "https:" + src
        } else if src.hasPrefix("/"), let baseURL = URL(string: item.link),
                  let resolved = URL(string: src, relativeTo: baseURL) {
            src = resolved.absoluteString
        }
        
        // Skip tracking pixels
        let width = Int((try? element.attr("width")) ?? "") ?? 999
        let height = Int((try? element.attr("height")) ?? "") ?? 999
        let isTracker = (width <= 2 && height <= 2) || src.contains("1x1") || src.contains("pixel") || src.contains("tracking")
        
        guard !isTracker, let url = URL(string: src) else { return nil }
        
        // Caption: only use explicit figcaption, skip alt text (often too long/aria-like)
        let caption = figcaption?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return .image(url, caption: (caption?.isEmpty ?? true) ? nil : caption)
    }
    
    // MARK: - Content Loading
    
    private func loadFullContent() async {
        // Try to fetch article content from the URL
        let link = item.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link), (url.scheme == "http" || url.scheme == "https") else {
            if item.description.isEmpty && (contentBlocks ?? []).isEmpty {
                loadFailed = true
            }
            return
        }
        
        isLoadingContent = true
        defer { isLoadingContent = false }
        
        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return }
            
            // Parse on background thread to avoid blocking the main thread
            let itemTitle = item.title
            let result: (html: String, text: String, blocks: [ContentBlock])? = await Task.detached(priority: .userInitiated) {
                let (extractedHTML, extractedText) = self.extractArticleContent(from: html)
                guard !extractedText.isEmpty else { return nil }
                let blocks = self.parseContentBlocks(from: extractedHTML, articleTitle: itemTitle)
                return (extractedHTML, extractedText, blocks)
            }.value
            
            if let result {
                fullContentHTML = result.html
                fullContent = result.text
                if !result.blocks.isEmpty {
                    contentBlocks = result.blocks
                }
            }
        } catch {
            if item.description.isEmpty && (contentBlocks ?? []).isEmpty {
                loadFailed = true
            }
        }
    }
    
    /// Extracts the main content area from a full HTML page using SwiftSoup. Returns (rawHTML, strippedText).
    nonisolated private func extractArticleContent(from html: String) -> (String, String) {
        return autoreleasepool {
            // Cap input to prevent parsing extremely large pages
            let cappedHTML = html.count > 1_000_000 ? String(html.prefix(1_000_000)) : html
            guard let doc = try? SwiftSoup.parse(cappedHTML) else { return ("", "") }
            
            // Remove junk
            _ = try? doc.select("script, style, nav, footer, header, aside, form, button, input, select, textarea, svg, iframe, object, embed, applet, template, noscript, [role=navigation], [role=banner], [role=complementary], [aria-hidden=true], .sidebar, .ad, .advertisement, .social-share, .related-posts, .newsletter-signup, .comments, .breadcrumb, .pagination, .dropdown, .dropdown-menu, .flash, .sr-only").remove()
        
        // Try to find the main content container
        let selectors = [
            "article",
            "main",
            "[class*=post-content]",
            "[class*=entry-content]",
            "[class*=article-body]",
            "[class*=article-content]",
            "[class*=story-body]",
            "[class*=post-body]",
            "[role=main]",
        ]
        
        for selector in selectors {
            if let element = try? doc.select(selector).first(),
               let contentHTML = try? element.html(),
               let contentText = try? element.text(),
               contentText.count > 100 {
                return (contentHTML, contentText)
            }
        }
        
            // Fallback: use body content
            if let body = doc.body(),
               let bodyHTML = try? body.html(),
               let bodyText = try? body.text(),
               bodyText.count > 100 {
                return (bodyHTML, bodyText)
            }
            
            return ("", "")
        } // autoreleasepool
    }
}
