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

// MARK: - View Modifiers

struct MenuBarWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .popover
        return visualEffect
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct AppearanceApplier: NSViewRepresentable {
    let appearanceMode: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.applyAppearance()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.applyAppearance()
        }
    }

    private func applyAppearance() {
        let appearance: NSAppearance? = switch appearanceMode {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
        NSApp.appearance = appearance
    }
}

struct HeaderButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .medium))
            .buttonStyle(.borderless)
    }
}

struct FeedItemContextMenu: ViewModifier {
    let item: FeedItem
    let store: FeedStore
    
    func body(content: Content) -> some View {
        content
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
    }
}

struct SectionDivider: ViewModifier {
    var alignment: Alignment = .bottom
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.primary.opacity(0.1)),
                alignment: alignment
            )
    }
}

extension View {
    func headerButtonStyle() -> some View {
        modifier(HeaderButtonStyle())
    }
    
    func feedItemContextMenu(item: FeedItem, store: FeedStore) -> some View {
        modifier(FeedItemContextMenu(item: item, store: store))
    }
    
    func sectionDivider(alignment: Alignment = .bottom) -> some View {
        modifier(SectionDivider(alignment: alignment))
    }
}

// MARK: - Main View

struct RSSReaderView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredItemId: UUID?

    var body: some View {
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
        .background(VisualEffectBackground())
        .background(MenuBarWindowConfigurator())
        .background(AppearanceApplier(appearanceMode: store.appearanceMode))
        .frame(width: 380, height: 520)
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
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 12) {
                headerButton("Refresh feeds", icon: store.isRefreshing 
                    ? "arrow.trianglehead.2.clockwise.rotate.90" 
                    : "arrow.clockwise") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r")
                .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)

                headerButton("Preferences", icon: "gearshape.fill") {
                    openWindow(id: "preferences")
                }
                .keyboardShortcut(",")

                headerButton("Mark all as read", icon: "checkmark.circle.fill") {
                    store.markAllAsRead()
                }
                .disabled(store.unreadCount == 0)

                headerButton("Quit", icon: "xmark.circle.fill") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .sectionDivider()
    }

    // MARK: - Filter Tabs View

    private var filterTabsView: some View {
        Picker("Filter", selection: $store.filter.animation(.easeInOut(duration: 0.2))) {
            ForEach(FeedFilter.allCases, id: \.self) { filter in
                Label {
                    Text(filter.rawValue)
                } icon: {
                    Image(systemName: filter.icon)
                }
                .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
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
                    .feedItemContextMenu(item: item, store: store)
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
        .sectionDivider(alignment: .top)
    }

    // MARK: - Helper Methods
    
    private func headerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .headerButtonStyle()
        .help(title)
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
        .sectionDivider()
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


