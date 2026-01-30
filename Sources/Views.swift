import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Colors

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255,
            opacity: Double(a) / 255)
    }
}

// MARK: - Glass Effect Components

struct GlassBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}

// MARK: - Main View

struct RSSReaderView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("rssAppearanceMode") private var appearanceMode: String = "system"
    @State private var hoveredItemId: UUID?

    var body: some View {
        ZStack {
            GlassBackground()
            
            VStack(spacing: 0) {
                headerView
                
                filterTabsView
                
                Divider()
                
                if store.filteredItems.isEmpty {
                    emptyStateView
                } else {
                    itemListView
                }
                
                Divider()
                
                footerView
            }
        }
        .frame(width: 380, height: 520)
        .preferredColorScheme(colorScheme)
        .alert("Error", isPresented: $store.showingError) {
            Button("OK") { store.showingError = false }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred.")
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 18))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 4) {
                HeaderButton(
                    systemImage: store.isRefreshing 
                        ? "arrow.trianglehead.2.clockwise.rotate.90" 
                        : "arrow.clockwise",
                    help: "Refresh feeds",
                    isAnimating: store.isRefreshing
                ) {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r")

                HeaderButton(
                    systemImage: "gearshape.fill",
                    help: "Preferences"
                ) {
                    openWindow(id: "preferences")
                }
                .keyboardShortcut(",")

                HeaderButton(
                    systemImage: "checkmark.circle.fill",
                    help: "Mark all as read",
                    isDisabled: store.unreadCount == 0
                ) {
                    store.markAllAsRead()
                }

                HeaderButton(
                    systemImage: "xmark.circle.fill",
                    help: "Quit"
                ) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.primary.opacity(0.1)),
            alignment: .bottom
        )
    }

    // MARK: - Filter Tabs View

    private var filterTabsView: some View {
        HStack(spacing: 4) {
            ForEach(FeedFilter.allCases, id: \.self) { filterOption in
                filterTab(filterOption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private func filterTab(_ filterOption: FeedFilter) -> some View {
        FilterTabButton(filterOption: filterOption, store: store)
    }

    // MARK: - Item List View

    private var itemListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.filteredItems) { item in
                    FeedItemRow(
                        item: item,
                        feedTitle: store.feedTitle(for: item),
                        isHovered: hoveredItemId == item.id,
                        fontSize: store.fontSize
                    )
                    .onTapGesture {
                        store.openItem(item)
                    }
                    .contextMenu {
                        Button(item.isRead ? "Mark as Unread" : "Mark as Read") {
                            store.toggleRead(item)
                        }
                        Button(item.isStarred ? "Unstar" : "Star") {
                            store.toggleStarred(item)
                        }
                        Divider()
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.link, forType: .string)
                        }
                    }
                    .onHover { isHovered in
                        hoveredItemId = isHovered ? item.id : nil
                    }
                }
            }
            .padding(.vertical, 0)
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: store.filter == .starred ? "star.slash" : "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(emptyStateMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if store.feeds.isEmpty {
                Button("Add Feeds") {
                    openWindow(id: "preferences")
                }
                .buttonStyle(.borderedProminent)
            } else if store.filter == .all {
                Button("Refresh") {
                    Task { await store.refreshAll() }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        switch store.filter {
        case .all:
            return store.feeds.isEmpty
                ? "No feeds added yet.\nAdd some feeds to get started."
                : "No items to show.\nTry refreshing your feeds."
        case .unread:
            return "All caught up!\nNo unread items."
        case .starred:
            return "No starred items.\nStar items to save them here."
        }
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text("All Unread")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)

            Spacer()

            if let lastRefresh = store.lastRefreshTime {
                Text(relativeTimeString(from: lastRefresh))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if store.unreadCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("\(store.unreadCount)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.primary.opacity(0.1)),
            alignment: .top
        )
    }

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Feed Item Row

struct FeedItemRow: View {
    let item: FeedItem
    let feedTitle: String
    let isHovered: Bool
    let fontSize: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.isRead ? Color.clear : Color.blue)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    if item.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }

                    Text(item.title)
                        .font(.system(size: fontSize, weight: item.isRead ? .regular : .semibold))
                        .foregroundStyle(.primary.opacity(item.isRead ? 0.7 : 1.0))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 8) {
                    Text(feedTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let pubDate = item.pubDate {
                        Text("•")
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text(formatDate(pubDate))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.primary.opacity(0.08)),
            alignment: .bottom
        )
        .contentShape(Rectangle())
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
}

// MARK: - Filter Tab Button

struct FilterTabButton: View {
    let filterOption: FeedFilter
    @ObservedObject var store: FeedStore
    @State private var isHovered: Bool = false

    var body: some View {
        let isSelected = store.filter == filterOption
        let count: Int = {
            switch filterOption {
            case .all: return store.items.count
            case .unread: return store.unreadCount
            case .starred: return store.starredCount
            }
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.filter = filterOption
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filterOption.icon)
                    .font(.system(size: 11, weight: .medium))

                Text(filterOption.rawValue)
                    .font(.system(size: 12, weight: .medium))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Header Button

struct HeaderButton: View {
    let systemImage: String
    let help: String
    var isDisabled: Bool = false
    var isAnimating: Bool = false
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                )
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    isAnimating 
                        ? .linear(duration: 1).repeatForever(autoreverses: false) 
                        : .default,
                    value: isAnimating
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var foregroundColor: Color {
        if isDisabled {
            return Color.secondary.opacity(0.5)
        } else if isHovered {
            return Color.primary
        } else {
            return Color.secondary
        }
    }
}
