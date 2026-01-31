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
    
    init(nsColor: NSColor) {
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
            return
        }
        self.init(
            .sRGB,
            red: Double(rgbColor.redComponent),
            green: Double(rgbColor.greenComponent),
            blue: Double(rgbColor.blueComponent),
            opacity: Double(rgbColor.alphaComponent)
        )
    }
    
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else {
            return "007AFF"
        }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
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
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(material: NSVisualEffectView.Material = .hudWindow, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = material
        visualEffect.blendingMode = blendingMode
        visualEffect.state = .active
        return visualEffect
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
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
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .glassEffect(
                    isHovered ? .regular.interactive().tint(.primary.opacity(0.15)) : .regular.interactive(),
                    in: .circle
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        } else {
            content
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(.borderless)
        }
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

// MARK: - Filter Tab Button (macOS 26+)

@available(macOS 26.0, *)
struct FilterTabButton: View {
    let filter: FeedFilter
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Label {
                Text(filter.rawValue)
            } icon: {
                Image(systemName: filter.icon)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .glassEffect(
            isSelected 
                ? .regular.interactive() 
                : (isHovered ? .clear.interactive().tint(.primary.opacity(0.12)) : .clear.interactive()),
            in: .capsule
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Refresh Button

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .modifier(RefreshButtonGlassModifier(isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Refresh feeds")
    }
}

struct RefreshButtonGlassModifier: ViewModifier {
    let isHovered: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    isHovered ? .regular.interactive().tint(.primary.opacity(0.15)) : .regular.interactive(),
                    in: .circle
                )
        } else {
            content
        }
    }
}

// MARK: - Footer Button (macOS 26+)

@available(macOS 26.0, *)
struct FooterGlassButton: View {
    let title: String
    let icon: String
    let action: (() -> Void)?
    @State private var isHovered = false
    
    var body: some View {
        Button {
            action?()
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .glassEffect(
            isHovered ? .regular.interactive().tint(.primary.opacity(0.15)) : .regular.interactive(),
            in: .capsule
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(title)
    }
}

// MARK: - Window Helper

func openPreferencesWindow(openWindow: OpenWindowAction) {
    // First, try to bring existing window to front
    if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" }) {
        existingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    } else {
        // If window doesn't exist, open it
        openWindow(id: "preferences")
        // Give it a moment to create, then bring to front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let newWindow = NSApp.windows.first(where: { $0.title == "Preferences" }) {
                newWindow.identifier = NSUserInterfaceItemIdentifier("preferences")
                newWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// MARK: - Main View

struct RSSReaderView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredItemId: UUID?

    @ViewBuilder
    var body: some View {
        let content = VStack(spacing: 0) {
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

        if #available(macOS 26.0, *) {
            content
                .background(.ultraThinMaterial)
                .background(MenuBarWindowConfigurator())
                .background(AppearanceApplier(appearanceMode: store.appearanceMode))
                .frame(width: 380, height: 520)
                .alert("Error", isPresented: $store.showingError) {
                    Button("OK") { store.showingError = false }
                } message: {
                    Text(store.errorMessage ?? "An unknown error occurred.")
                }
        } else {
            content
                .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
                .background(MenuBarWindowConfigurator())
                .background(AppearanceApplier(appearanceMode: store.appearanceMode))
                .frame(width: 380, height: 520)
                .alert("Error", isPresented: $store.showingError) {
                    Button("OK") { store.showingError = false }
                } message: {
                    Text(store.errorMessage ?? "An unknown error occurred.")
                }
        }
    }

    // MARK: - Header View

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 18))
                .foregroundStyle(.primary)

            Spacer()

            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        RefreshButton(isRefreshing: store.isRefreshing) {
                            Task { await store.refreshAll() }
                        }
                        .keyboardShortcut("r")

                        headerButton("Preferences", icon: "gearshape.fill") {
                            openPreferencesWindow(openWindow: openWindow)
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
            } else {
                HStack(spacing: 12) {
                    RefreshButton(isRefreshing: store.isRefreshing) {
                        Task { await store.refreshAll() }
                    }
                    .keyboardShortcut("r")

                    headerButton("Preferences", icon: "gearshape.fill") {
                        openPreferencesWindow(openWindow: openWindow)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .sectionDivider()
    }

    // MARK: - Filter Tabs View

    @ViewBuilder
    private var filterTabsView: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(FeedFilter.allCases, id: \.self) { filter in
                        FilterTabButton(
                            filter: filter,
                            isSelected: store.filter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.filter = filter
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        } else {
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
                        fontSize: store.fontSize,
                        highlightColor: store.highlightColor(for: item),
                        iconEmoji: store.iconEmoji(for: item),
                        showSummary: store.shouldShowSummary(for: item)
                    )
                    .onTapGesture {
                        store.openItem(item)
                    }
                    .feedItemContextMenu(item: item, store: store)
                    .onHover { isHovered in
                        hoveredItemId = isHovered ? item.id : nil
                    }
                }
                
                // Hidden items indicator
                if store.hiddenItemCount > 0 {
                    HStack {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 11))
                        Text("\(store.hiddenItemCount) items hidden by filters")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
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
                if #available(macOS 26.0, *) {
                    Button("Add Feeds") {
                        openPreferencesWindow(openWindow: openWindow)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button("Add Feeds") {
                        openPreferencesWindow(openWindow: openWindow)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if store.filter == .all {
                if #available(macOS 26.0, *) {
                    Button("Refresh") {
                        Task { await store.refreshAll() }
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button("Refresh") {
                        Task { await store.refreshAll() }
                    }
                    .buttonStyle(.borderedProminent)
                }
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

    @ViewBuilder
    private var footerView: some View {
        HStack {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        FooterGlassButton(title: "Feeds", icon: "list.bullet", action: nil)
                        FooterGlassButton(title: "Settings", icon: "gearshape") {
                            openPreferencesWindow(openWindow: openWindow)
                        }
                        FooterGlassButton(title: "Help", icon: "questionmark.circle", action: nil)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("All Unread")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }

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
        let seconds = Int(Date().timeIntervalSince(date))
        
        // Handle very recent times explicitly
        if seconds < 2 {
            return "just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        }
        
        // Use system formatter for longer durations
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
    let highlightColor: Color?
    let iconEmoji: String?
    let showSummary: Bool

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
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if showSummary && !item.description.isEmpty {
                    Text(item.description)
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(feedTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Date aligned to the right on same row as feed name
                    if let pubDate = item.pubDate {
                        Text(formatDate(pubDate))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            ZStack {
                if let emoji = iconEmoji {
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
