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

@available(macOS 26.0, *)
struct GlassEffectContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .clipShape(Capsule())
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
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
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
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
    }
}

struct HeaderButtonHoverModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .foregroundStyle(.primary)
                .background(isHovered ? Color.primary.opacity(0.12) : Color.clear)
                .clipShape(Circle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        } else {
            content
        }
    }
}

struct FeedItemContextMenu: ViewModifier {
    let item: FeedItem
    let store: FeedStore
    
    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(item.isRead ? String(localized: "Mark as Unread", bundle: .module) : String(localized: "Mark as Read", bundle: .module)) {
                    store.toggleRead(item)
                }
                Button(item.isStarred ? String(localized: "Unstar", bundle: .module) : String(localized: "Star", bundle: .module)) {
                    store.toggleStarred(item)
                }
                Divider()
                Button(String(localized: "Mark all above as read", bundle: .module)) {
                    store.markItemsAboveAsRead(item)
                }
                .disabled(store.filteredItems.first?.id == item.id)
                Button(String(localized: "Mark all below as read", bundle: .module)) {
                    store.markItemsBelowAsRead(item)
                }
                .disabled(store.filteredItems.last?.id == item.id)
                Divider()
                Button(String(localized: "Share", bundle: .module)) {
                    store.shareItem(item)
                }
                Button(String(localized: "Copy Link", bundle: .module)) {
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
                Text(filter.localizedName)
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
        .background(isSelected ? Color.primary.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
        .clipShape(Capsule())
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
            // TimelineView properly stops when paused, unlike repeatForever animations
            TimelineView(.animation(paused: !isRefreshing)) { context in
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isRefreshing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
            }
            .font(.system(size: 14, weight: .medium))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .modifier(RefreshButtonGlassModifier(isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(String(localized: "Refresh feeds", bundle: .module))
        .accessibilityLabel(String(localized: "Refresh feeds", bundle: .module))
    }
}

struct RefreshButtonGlassModifier: ViewModifier {
    let isHovered: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(isHovered ? Color.primary.opacity(0.12) : Color.clear)
                .clipShape(Circle())
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
        .background(isHovered ? Color.primary.opacity(0.12) : Color.clear)
        .clipShape(Capsule())
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
        DispatchQueue.main.async {
            if let newWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" || $0.title == "Preferences" }) {
                newWindow.identifier = NSUserInterfaceItemIdentifier("preferences")
                newWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

func openAddFeedWindow(openWindow: OpenWindowAction) {
    if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" }) {
        existingWindow.makeKeyAndOrderFront(nil)
        existingWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    
    openWindow(id: "addFeed")
    
    DispatchQueue.main.async {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" || $0.title == "Add Feed" }) {
            window.identifier = NSUserInterfaceItemIdentifier("addFeed")
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Main View

struct RSSReaderView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredItemId: UUID?
    @AppStorage("rssPreferencesTab") private var preferencesTab: String = "feeds"

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
                .alert(String(localized: "Error", bundle: .module), isPresented: $store.showingError) {
                    Button(String(localized: "OK", bundle: .module)) { store.showingError = false }
                } message: {
                    Text(store.errorMessage ?? String(localized: "An unknown error occurred.", bundle: .module))
                }
        } else {
            content
                .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
                .background(MenuBarWindowConfigurator())
                .background(AppearanceApplier(appearanceMode: store.appearanceMode))
                .frame(width: 380, height: 520)
                .alert(String(localized: "Error", bundle: .module), isPresented: $store.showingError) {
                    Button(String(localized: "OK", bundle: .module)) { store.showingError = false }
                } message: {
                    Text(store.errorMessage ?? String(localized: "An unknown error occurred.", bundle: .module))
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
                HStack(spacing: 12) {
                    GlassEffectContainer {
                        HStack(spacing: 8) {
                            RefreshButton(isRefreshing: store.isRefreshing) {
                                Task { await store.refreshAll() }
                            }
                            .keyboardShortcut("r")
                            .accessibilityLabel(String(localized: "Refresh feeds", bundle: .module))

                            headerButton(String(localized: "Preferences", bundle: .module), icon: "gearshape.fill") {
                                preferencesTab = "feeds"
                                openPreferencesWindow(openWindow: openWindow)
                            }
                            .keyboardShortcut(",")
                            .accessibilityLabel(String(localized: "Preferences", bundle: .module))

                            headerButton(String(localized: "Mark all as read", bundle: .module), icon: "checklist") {
                                store.markAllAsRead()
                            }
                            .disabled(store.unreadCount == 0)
                            .accessibilityLabel(String(localized: "Mark all as read", bundle: .module))
                        }
                    }

                    headerButton(String(localized: "Quit", bundle: .module), icon: "xmark.circle.fill") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                    .accessibilityLabel(String(localized: "Quit", bundle: .module))
                }
            } else {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        RefreshButton(isRefreshing: store.isRefreshing) {
                            Task { await store.refreshAll() }
                        }
                        .keyboardShortcut("r")
                        .accessibilityLabel(String(localized: "Refresh feeds", bundle: .module))

                        headerButton(String(localized: "Preferences", bundle: .module), icon: "gearshape.fill") {
                            preferencesTab = "feeds"
                            openPreferencesWindow(openWindow: openWindow)
                        }
                        .keyboardShortcut(",")
                        .accessibilityLabel(String(localized: "Preferences", bundle: .module))

                        headerButton(String(localized: "Mark all as read", bundle: .module), icon: "checklist") {
                            store.markAllAsRead()
                        }
                        .disabled(store.unreadCount == 0)
                        .accessibilityLabel(String(localized: "Mark all as read", bundle: .module))
                    }

                    headerButton(String(localized: "Quit", bundle: .module), icon: "xmark.circle.fill") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                    .accessibilityLabel(String(localized: "Quit", bundle: .module))
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
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Filter", bundle: .module))
        } else {
            Picker(String(localized: "Filter", bundle: .module), selection: $store.filter.animation(.easeInOut(duration: 0.2))) {
                ForEach(FeedFilter.allCases, id: \.self) { filter in
                    Label {
                        Text(filter.localizedName)
                    } icon: {
                        Image(systemName: filter.icon)
                    }
                    .tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
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
                        feedIconURL: store.feedIconURL(for: item),
                        feedURL: store.feedURL(for: item),
                        isHovered: hoveredItemId == item.id,
                        fontSize: store.fontSize,
                        titleMaxLines: store.titleMaxLines,
                        timeFormat: store.timeFormat,
                        highlightColor: store.highlightColor(for: item),
                        iconEmoji: store.iconEmoji(for: item),
                        showSummary: store.shouldShowSummary(for: item),
                        showFeedIcon: store.showFeedIcons
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
                        Text(String(format: String(localized: "%lld items hidden by filters", bundle: .module), store.hiddenItemCount))
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
                    Button(String(localized: "Add Feeds", bundle: .module)) {
                        preferencesTab = "feeds"
                        openPreferencesWindow(openWindow: openWindow)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button(String(localized: "Add Feeds", bundle: .module)) {
                        preferencesTab = "feeds"
                        openPreferencesWindow(openWindow: openWindow)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if store.filter == .all {
                if #available(macOS 26.0, *) {
                    Button(String(localized: "Refresh", bundle: .module)) {
                        Task { await store.refreshAll() }
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button(String(localized: "Refresh", bundle: .module)) {
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
                ? String(localized: "No feeds added yet.\nAdd some feeds to get started.", bundle: .module)
                : String(localized: "No items to show.\nTry refreshing your feeds.", bundle: .module)
        case .unread:
            return String(localized: "All caught up!\nNo unread items.", bundle: .module)
        case .starred:
            return String(localized: "No starred items.\nStar items to save them here.", bundle: .module)
        }
    }

    // MARK: - Footer View

    @ViewBuilder
    private var footerView: some View {
        HStack {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        FooterGlassButton(title: String(localized: "Filter", bundle: .module), icon: "line.3.horizontal.decrease.circle") {
                            preferencesTab = "filters"
                            openPreferencesWindow(openWindow: openWindow)
                        }
                        .keyboardShortcut("f", modifiers: [.command])
                        .accessibilityLabel(String(localized: "Filter", bundle: .module))
                        FooterGlassButton(title: String(localized: "Add Feed", bundle: .module), icon: "plus") {
                            openAddFeedWindow(openWindow: openWindow)
                        }
                        .keyboardShortcut("n", modifiers: [.command])
                        .accessibilityLabel(String(localized: "Add Feed", bundle: .module))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        preferencesTab = "filters"
                        openPreferencesWindow(openWindow: openWindow)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Filter", bundle: .module))
                    .accessibilityLabel(String(localized: "Filter", bundle: .module))
                    .keyboardShortcut("f", modifiers: [.command])
                    
                    Button {
                        openAddFeedWindow(openWindow: openWindow)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Add Feed", bundle: .module))
                    .accessibilityLabel(String(localized: "Add Feed", bundle: .module))
                    .keyboardShortcut("n", modifiers: [.command])
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
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HeaderButtonHoverModifier())
        .help(title)
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        // Handle very recent times explicitly
        if seconds < 2 {
            return String(localized: "just now", bundle: .module)
        } else if seconds < 60 {
            return String(format: String(localized: "%llds ago", bundle: .module), seconds)
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
}
