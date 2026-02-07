import AppKit
import SwiftSoup
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
struct GlassCapsule<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
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
    
    func pointerOnHover() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct CapsuleGlassModifier: ViewModifier {
    let isActive: Bool
    let isHovered: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    isActive ? .regular.interactive().tint(.primary.opacity(0.15)) : .regular.interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(isActive ? Color.primary.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                .clipShape(Capsule())
        }
    }
}

struct BadgeGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassEffect(.regular.tint(.blue.opacity(0.2)), in: .capsule)
        } else {
            content
        }
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
        .modifier(CapsuleGlassModifier(isActive: isSelected, isHovered: isHovered))
        .pointerOnHover()
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
        .pointerOnHover()
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
        .background(isHovered ? Color.primary.opacity(0.12) : Color.clear)
        .clipShape(Capsule())
        .pointerOnHover()
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
    // LSUIElement apps must switch to .regular to receive keyboard input and appear in front
    NSApp.setActivationPolicy(.regular)
    
    // First, try to bring existing window to front
    if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" }) {
        existingWindow.level = .floating
        existingWindow.makeKeyAndOrderFront(nil)
        existingWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    } else {
        // If window doesn't exist, open it
        openWindow(id: "preferences")
        DispatchQueue.main.async {
            if let newWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" || $0.title == "Preferences" }) {
                newWindow.identifier = NSUserInterfaceItemIdentifier("preferences")
                newWindow.level = .floating
                newWindow.makeKeyAndOrderFront(nil)
                newWindow.orderFrontRegardless()
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
    @State private var selectedItemId: UUID?
    @State private var showingFeedPicker: Bool = false
    @State private var hoveredPickerFeedId: UUID?
    @State private var feedPickerHovered: Bool = false
    @State private var previewingItem: FeedItem? = nil
    @AppStorage("rssPreferencesTab") private var preferencesTab: String = "feeds"

    @ViewBuilder
    var body: some View {
        let content = VStack(spacing: 0) {
            if let item = previewingItem {
                ArticlePreviewPane(
                    item: item,
                    feedTitle: store.feedTitle(for: item),
                    store: store,
                    onClose: { withAnimation(.easeInOut(duration: 0.2)) { previewingItem = nil } }
                )
            } else {
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
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.return) { openSelectedItem(); return .handled }
        .onKeyPress(.space) { toggleSelectedRead(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "s")) { _ in toggleSelectedStar(); return .handled }
        .onKeyPress(.escape) {
            if previewingItem != nil {
                withAnimation(.easeInOut(duration: 0.2)) { previewingItem = nil }
                return .handled
            }
            return .ignored
        }
        .focusable()
        .focusEffectDisabled()

        if #available(macOS 26.0, *) {
            content
                .background(.ultraThinMaterial)
                .background(MenuBarWindowConfigurator())
                .background(AppearanceApplier(appearanceMode: store.appearanceMode))
                .frame(width: store.windowWidth, height: store.windowHeight)
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
                .frame(width: store.windowWidth, height: store.windowHeight)
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

                            headerButton(String(localized: "Mark all as read", bundle: .module), icon: "text.badge.checkmark") {
                                store.markAllAsRead()
                            }
                            .disabled(store.unreadCount == 0)
                            .accessibilityLabel(String(localized: "Mark all as read", bundle: .module))

                            headerButton(String(localized: "Add Feed", bundle: .module), icon: "plus") {
                                openAddFeedWindow(openWindow: openWindow)
                            }
                            .keyboardShortcut("n", modifiers: [.command])
                            .accessibilityLabel(String(localized: "Add Feed", bundle: .module))

                            headerButton(String(localized: "Preferences", bundle: .module), icon: "gearshape.fill") {
                                preferencesTab = "feeds"
                                openPreferencesWindow(openWindow: openWindow)
                            }
                            .keyboardShortcut(",")
                            .accessibilityLabel(String(localized: "Preferences", bundle: .module))
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

                        headerButton(String(localized: "Mark all as read", bundle: .module), icon: "text.badge.checkmark") {
                            store.markAllAsRead()
                        }
                        .disabled(store.unreadCount == 0)
                        .accessibilityLabel(String(localized: "Mark all as read", bundle: .module))

                        headerButton(String(localized: "Add Feed", bundle: .module), icon: "plus") {
                            openAddFeedWindow(openWindow: openWindow)
                        }
                        .keyboardShortcut("n", modifiers: [.command])
                        .accessibilityLabel(String(localized: "Add Feed", bundle: .module))

                        headerButton(String(localized: "Preferences", bundle: .module), icon: "gearshape.fill") {
                            preferencesTab = "feeds"
                            openPreferencesWindow(openWindow: openWindow)
                        }
                        .keyboardShortcut(",")
                        .accessibilityLabel(String(localized: "Preferences", bundle: .module))
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
                        showFeedIcon: store.showFeedIcons,
                        onPreview: {
                            store.markAsRead(item)
                            withAnimation(.easeInOut(duration: 0.2)) { previewingItem = item }
                        }
                    )
                    .background(selectedItemId == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    .onTapGesture {
                        selectedItemId = item.id
                        store.openItem(item)
                    }
                    .feedItemContextMenu(item: item, store: store)
                    .pointerOnHover()
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

    // MARK: - Feed Picker Popover
    
    private var feedPickerPopover: some View {
        let allItemsId = UUID() // sentinel for "All Feeds" hover
        return VStack(spacing: 0) {
            Button {
                store.selectedFeedId = nil
                showingFeedPicker = false
            } label: {
                HStack {
                    Text(String(localized: "All Feeds", bundle: .module))
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(store.items.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if store.selectedFeedId == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(hoveredPickerFeedId == allItemsId ? Color.primary.opacity(0.08) : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
            .onHover { isHovered in
                hoveredPickerFeedId = isHovered ? allItemsId : nil
            }
            
            Divider()
            
            ForEach(store.feeds) { feed in
                let itemCount = store.items.filter { $0.feedId == feed.id }.count
                Button {
                    store.selectedFeedId = feed.id
                    showingFeedPicker = false
                } label: {
                    HStack {
                        Text(feed.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text("\(itemCount)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if store.selectedFeedId == feed.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hoveredPickerFeedId == feed.id ? Color.primary.opacity(0.08) : Color.clear)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .onHover { isHovered in
                    hoveredPickerFeedId = isHovered ? feed.id : nil
                }
            }
        }
        .frame(width: 220)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    // MARK: - Footer View

    @ViewBuilder
    private var footerView: some View {
        let feedLabel: String = {
            if let id = store.selectedFeedId,
               let feed = store.feeds.first(where: { $0.id == id }) {
                return String(feed.title.prefix(25))
            }
            return String(localized: "All Feeds", bundle: .module)
        }()
        
        HStack {
            Button {
                showingFeedPicker.toggle()
            } label: {
                Label {
                    Text(feedLabel)
                } icon: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.selectedFeedId != nil ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(CapsuleGlassModifier(isActive: store.selectedFeedId != nil, isHovered: feedPickerHovered))
            .pointerOnHover()
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    feedPickerHovered = hovering
                }
            }
            .help(String(localized: "Select Feed", bundle: .module))
            .accessibilityLabel(String(localized: "Select Feed", bundle: .module))
            .popover(isPresented: $showingFeedPicker) {
                feedPickerPopover
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
                .modifier(BadgeGlassModifier())
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
        .pointerOnHover()
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
    
    // MARK: - Keyboard Navigation
    
    private func moveSelection(by offset: Int) {
        let items = store.filteredItems
        guard !items.isEmpty else { return }
        
        if let currentId = selectedItemId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }) {
            let newIndex = max(0, min(items.count - 1, currentIndex + offset))
            selectedItemId = items[newIndex].id
        } else {
            selectedItemId = offset > 0 ? items.first?.id : items.last?.id
        }
    }
    
    private func openSelectedItem() {
        guard let id = selectedItemId,
              let item = store.filteredItems.first(where: { $0.id == id }) else { return }
        store.openItem(item)
    }
    
    private func toggleSelectedRead() {
        guard let id = selectedItemId,
              let item = store.filteredItems.first(where: { $0.id == id }) else { return }
        store.toggleRead(item)
    }
    
    private func toggleSelectedStar() {
        guard let id = selectedItemId,
              let item = store.filteredItems.first(where: { $0.id == id }) else { return }
        store.toggleStarred(item)
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
                        .font(.system(size: 10, weight: .medium))
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
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            ZStack {
                if isHovered, onPreview != nil {
                    Button {
                        onPreview?()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Preview", bundle: .module))
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

// MARK: - Article Preview Pane

struct ArticlePreviewPane: View {
    let item: FeedItem
    let feedTitle: String
    @ObservedObject var store: FeedStore
    let onClose: () -> Void
    
    @State private var fullContent: String?
    @State private var fullContentHTML: String?
    @State private var isLoadingContent = false
    @State private var contentBlocks: [ContentBlock]?
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
                let blocks = await Task.detached(priority: .userInitiated) {
                    self.parseContentBlocks(from: html)
                }.value
                if !blocks.isEmpty {
                    contentBlocks = blocks
                }
            }
            // Then try fetching full article if feed content is sparse
            await loadFullContent()
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
                    Label(String(localized: "Back", bundle: .module), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
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
                    Label(String(localized: "Back", bundle: .module), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                // Article header
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
                
                Divider()
                
                // Article body — rendered as cached content blocks
                let blocks = contentBlocks ?? []
                
                if loadFailed {
                    // Error state — couldn't load article
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Couldn't load article", bundle: .module))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Open in Browser", bundle: .module)) {
                            store.openItem(item)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if blocks.isEmpty && !isLoadingContent {
                    // Fallback to plain text description
                    let content = fullContent ?? item.description
                    if content.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 32))
                                .foregroundStyle(.quaternary)
                            Text(String(localized: "No preview available", bundle: .module))
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Button(String(localized: "Open in Browser", bundle: .module)) {
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
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let text):
                            if !text.isEmpty {
                                Text(text)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .lineSpacing(6)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        case .heading(let text, let level):
                            Text(text)
                                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, level <= 2 ? 8 : 4)
                        case .blockquote(let text):
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.accentColor.opacity(0.5))
                                    .frame(width: 3)
                                Text(text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 12)
                            }
                            .padding(.vertical, 4)
                        case .image(let url, let caption):
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
                        case .code(let code):
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
                    }
                }
                
                if isLoadingContent {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Loading full article…", bundle: .module))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                
                // Categories/tags
                if !item.categories.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.categories.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 8)
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
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
        if seconds < 60 { return String(localized: "Just now", bundle: .module) }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: String(localized: "%lld min ago", bundle: .module), minutes) }
        let hours = minutes / 60
        if hours < 24 { return String(format: String(localized: "%lld hr ago", bundle: .module), hours) }
        let days = hours / 24
        if days < 7 { return String(format: String(localized: "%lld days ago", bundle: .module), days) }
        return Self.previewDateFormatter.string(from: date)
    }
    
    // MARK: - Content Block Parsing (SwiftSoup)
    
    private enum ContentBlock {
        case text(String)
        case heading(String, level: Int)
        case blockquote(String)
        case image(URL, caption: String?)
        case code(String)
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
    
    /// Parses HTML into alternating text and image blocks using SwiftSoup DOM parser
    nonisolated private func parseContentBlocks(from html: String?) -> [ContentBlock] {
        guard let html = html, !html.isEmpty else { return [] }
        
        return autoreleasepool {
            // Cap input to prevent parsing extremely large HTML
            let cappedHTML = html.count > 500_000 ? String(html.prefix(500_000)) : html
            
            guard let doc = try? SwiftSoup.parseBodyFragment(cappedHTML) else {
                return []
            }
            
            // Remove non-content elements
            _ = try? doc.select("script, style, nav, footer, .ad, .advertisement, .social-share, .related-posts, .newsletter-signup, .comments").remove()
            
            guard let body = doc.body() else { return [] }
        
        var blocks: [ContentBlock] = []
        
        // Walk top-level children, grouping into text/image blocks
        for child in body.children() {
            extractBlocks(from: child, into: &blocks)
        }
        
        // If no children were block elements, process the body as a whole
        if blocks.isEmpty, let text = try? body.text(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.text(text))
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
            if let text = try? element.text(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.heading(text.trimmingCharacters(in: .whitespacesAndNewlines), level: level))
            }
            return
        }
        
        // Handle blockquotes
        if tag == "blockquote" {
            if let text = try? element.text(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.blockquote(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
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
                blocks.append(.text(ownText.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        } else {
            // Pure text element — use SwiftSoup's .text() for clean whitespace handling
            if let text = try? element.text(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Merge with previous text block if consecutive
                if case .text(let prev) = blocks.last {
                    blocks[blocks.count - 1] = .text(prev + "\n\n" + trimmed)
                } else {
                    blocks.append(.text(trimmed))
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
        // Check if feed provides substantial HTML content
        let feedHTML = item.contentHTML ?? ""
        let isTruncated = feedHTML.hasSuffix("...") || feedHTML.hasSuffix("…") || feedHTML.hasSuffix("[…]") || feedHTML.hasSuffix("[...]")
        let hasCodeBlocks = feedHTML.contains("<pre") || feedHTML.contains("<code")
        // Always fetch full article if feed content has code blocks (better formatting from the web page)
        // or if content is sparse/truncated
        if feedHTML.count > 500 && !isTruncated && !hasCodeBlocks { return }
        
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
            let itemDesc = item.description
            let result: (html: String, text: String, blocks: [ContentBlock])? = await Task.detached(priority: .userInitiated) {
                let (extractedHTML, extractedText) = self.extractArticleContent(from: html)
                guard extractedText.count > itemDesc.count else { return nil }
                let blocks = self.parseContentBlocks(from: extractedHTML)
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
            _ = try? doc.select("script, style, nav, footer, header, aside, .sidebar, .ad, .advertisement, .social-share, .related-posts, .newsletter-signup, .comments").remove()
        
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
