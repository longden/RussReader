import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Colors

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

let rowColors: [Color] = [
    Color(hex: "#2D5A4A"),  // Teal green
    Color(hex: "#3D4A5C"),  // Slate blue
    Color(hex: "#4A3D5C"),  // Purple
    Color(hex: "#5C3D4A"),  // Rose
    Color(hex: "#4A5C3D"),  // Olive
]

// MARK: - Main View

struct RSSReaderView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredItemId: UUID?
    
    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            filterTabsView
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            
            if store.filteredItems.isEmpty {
                emptyStateView
            } else {
                itemListView
            }
            
            footerView
        }
        .frame(width: 380, height: 520)
        .background(Color(hex: store.backgroundColorHex))
        .alert("Error", isPresented: $store.showingError) {
            Button("OK") { store.showingError = false }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred.")
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.9))
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: store.isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r")
                .help("Refresh feeds")
                
                Button {
                    openWindow(id: "preferences")
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",")
                .help("Preferences")
                
                Button {
                    store.markAllAsRead()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Mark all as read")
                .disabled(store.unreadCount == 0)
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .help("Quit")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(headerGradient)
    }
    
    // MARK: - Filter Tabs View
    
    private var filterTabsView: some View {
        HStack(spacing: 0) {
            ForEach(FeedFilter.allCases, id: \.self) { filterOption in
                filterTab(filterOption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.2))
    }
    
    private func filterTab(_ filterOption: FeedFilter) -> some View {
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
                        .background(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Item List View
    
    private var itemListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(store.filteredItems.enumerated()), id: \.element.id) { index, item in
                    FeedItemRow(
                        item: item,
                        feedTitle: store.feedTitle(for: item),
                        backgroundColor: rowColors[index % rowColors.count],
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
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: store.filter == .starred ? "star.slash" : "tray")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.3))
            
            Text(emptyStateMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
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
            return store.feeds.isEmpty ? "No feeds added yet.\nAdd some feeds to get started." : "No items to show.\nTry refreshing your feeds."
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
            .foregroundStyle(.white.opacity(0.5))
            
            Spacer()
            
            if let lastRefresh = store.lastRefreshTime {
                Text(relativeTimeString(from: lastRefresh))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            if store.unreadCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("\(store.unreadCount)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3))
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
    let backgroundColor: Color
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
                        .foregroundStyle(item.isRead ? .white.opacity(0.7) : .white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                HStack(spacing: 8) {
                    Text(feedTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    if let pubDate = item.pubDate {
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        Text(formatDate(pubDate))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor.opacity(isHovered ? 0.9 : 0.7))
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
