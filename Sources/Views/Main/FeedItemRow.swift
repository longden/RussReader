//
//  FeedItemRow.swift
//  RSSReader
//
//  Individual feed item row component
//

import SwiftUI

struct FeedItemRow: View {
    let item: FeedItem
    let feedTitle: String
    let feedIconURL: String?
    let feedURL: String?
    let isHovered: Bool
    let fontSize: Double
    let titleMaxLines: Int
    let timeFormat: String
    let highlightColor: Color?
    let iconEmoji: String?
    let showSummary: Bool
    let showFeedIcon: Bool
    let openInPreview: Bool
    var onPreview: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left indicator: star or unread dot (16pt wide to match right slot)
            ZStack {
                if item.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                } else if !item.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: fontSize, weight: item.isRead ? .regular : .semibold))
                    .foregroundStyle(.primary.opacity(item.isRead ? 0.7 : 1.0))
                    .lineLimit(titleMaxLines)
                    .multilineTextAlignment(.leading)

                if showSummary && !item.description.isEmpty {
                    Text(item.description)
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if showFeedIcon {
                        FeedIconView(iconURL: feedIconURL, feedURL: feedURL, size: 11)
                    }
                    Text(feedTitle)
                        .font(.system(size: fontSize - 3, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    // Enclosure indicator
                    if !item.enclosures.isEmpty {
                        Image(systemName: enclosureIcon(for: item.enclosures.first))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Date aligned to the right on same row as feed name
                    if let pubDate = item.pubDate {
                        Text(formatDate(pubDate))
                            .font(.system(size: fontSize - 3))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            ZStack {
                if isHovered, onPreview != nil {
                    Button {
                        onPreview?()
                    } label: {
                        Image(systemName: openInPreview ? "doc.text.magnifyingglass" : "globe")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(openInPreview ? String(localized: "Preview", bundle: .module) : String(localized: "Open in Browser", bundle: .module))
                } else if let emoji = iconEmoji {
                    Text(emoji)
                        .font(.system(size: 11))
                }
            }
            .frame(width: 16, height: 16)
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .sectionDivider()
        .contentShape(Rectangle())
    }
    
    private var rowBackground: some View {
        Group {
            if isHovered {
                Color.primary.opacity(0.08)
            } else if let color = highlightColor {
                color.opacity(0.12)
            } else {
                Color.clear
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return formatTime(date, timeFormat: timeFormat)
        } else if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday", bundle: .module)
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
    
    private static let timeFormatter12h: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let timeFormatter24h: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func formatTime(_ date: Date, timeFormat: String) -> String {
        let formatter = timeFormat == "24h" ? Self.timeFormatter24h : Self.timeFormatter12h
        return formatter.string(from: date)
    }
    
    private func enclosureIcon(for enclosure: Enclosure?) -> String {
        guard let enclosure = enclosure else { return "paperclip" }
        if enclosure.isAudio { return "headphones" }
        if enclosure.isVideo { return "video" }
        if enclosure.isImage { return "photo" }
        return "paperclip"
    }
}
