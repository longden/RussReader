import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Favicon Cache

final class FaviconCache {
    static let shared = FaviconCache()
    
    private let cache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL?
    
    private init() {
        cache.countLimit = 100
        
        // Set up disk cache directory
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let faviconDir = cachesDir.appendingPathComponent("FaviconCache", isDirectory: true)
            try? fileManager.createDirectory(at: faviconDir, withIntermediateDirectories: true)
            cacheDirectory = faviconDir
        } else {
            cacheDirectory = nil
        }
    }
    
    func image(for url: URL) -> NSImage? {
        let key = url.absoluteString as NSString
        
        // Check memory cache
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        // Check disk cache
        if let diskImage = loadFromDisk(for: url) {
            cache.setObject(diskImage, forKey: key)
            return diskImage
        }
        
        return nil
    }
    
    func store(_ image: NSImage, for url: URL) {
        let key = url.absoluteString as NSString
        cache.setObject(image, forKey: key)
        saveToDisk(image, for: url)
    }
    
    private func cacheFileURL(for url: URL) -> URL? {
        guard let cacheDirectory = cacheDirectory else { return nil }
        let filename = url.absoluteString.data(using: .utf8)?.base64EncodedString() ?? url.lastPathComponent
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    private func loadFromDisk(for url: URL) -> NSImage? {
        guard let fileURL = cacheFileURL(for: url),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }
    
    private func saveToDisk(_ image: NSImage, for url: URL) {
        guard let fileURL = cacheFileURL(for: url),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: fileURL)
    }
}

// MARK: - Feed Icon View

struct FeedIconView: View {
    let iconURL: String?
    let feedURL: String?
    let size: CGFloat
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    init(iconURL: String?, feedURL: String? = nil, size: CGFloat = 16) {
        self.iconURL = iconURL
        self.feedURL = feedURL
        self.size = size
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task {
            await loadIcon()
        }
    }
    
    private func loadIcon() async {
        guard !isLoading, image == nil else { return }
        isLoading = true
        defer { isLoading = false }
        
        // Try the feed-provided icon URL first
        if let iconURL = iconURL, let url = URL(string: iconURL) {
            if let loadedImage = await loadImageWithCache(from: url) {
                await MainActor.run { self.image = loadedImage }
                return
            }
        }
        
        // Fall back to favicon from the website
        if let feedURL = feedURL,
           let feedUrl = URL(string: feedURL),
           let host = feedUrl.host,
           let faviconURL = URL(string: "https://\(host)/favicon.ico") {
            if let loadedImage = await loadImageWithCache(from: faviconURL) {
                await MainActor.run { self.image = loadedImage }
            }
        }
    }
    
    private func loadImageWithCache(from url: URL) async -> NSImage? {
        // Check cache first
        if let cached = FaviconCache.shared.image(for: url) {
            return cached
        }
        
        // Fetch from network
        do {
            let request = URLRequest(url: url, timeoutInterval: defaultRequestTimeout)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = NSImage(data: data) {
                FaviconCache.shared.store(image, for: url)
                return image
            }
        } catch {
            // Silently fail - icon loading is non-critical
        }
        return nil
    }
}

// MARK: - Network Helpers

private let defaultRequestTimeout: TimeInterval = 15

// MARK: - Preferences View

struct PreferencesView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PreferencesTab = .feeds
    @AppStorage("rssPreferencesTab") private var preferencesTab: String = "feeds"
    
    enum PreferencesTab: CaseIterable {
        case feeds
        case filters
        case settings
        case help
        
        var title: String {
            switch self {
            case .feeds: return String(localized: "Feeds", bundle: .module)
            case .filters: return String(localized: "Filters", bundle: .module)
            case .settings: return String(localized: "Settings", bundle: .module)
            case .help: return String(localized: "Help", bundle: .module)
            }
        }
        
        var icon: String {
            switch self {
            case .feeds: return "link"
            case .filters: return "line.3.horizontal.decrease.circle"
            case .settings: return "gearshape"
            case .help: return "questionmark.circle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(String(localized: "Preferences", bundle: .module))
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 12)

            HStack(spacing: 16) {
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case .feeds:
                    FeedsTabView()
                case .filters:
                    FiltersTabView()
                case .settings:
                    SettingsTabView()
                case .help:
                    HelpTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .background(AppearanceApplier(appearanceMode: store.appearanceMode))
        .frame(width: 450, height: 500)
        .environmentObject(store)
        .onAppear {
            switch preferencesTab {
            case "filters":
                selectedTab = .filters
            case "settings":
                selectedTab = .settings
            case "help":
                selectedTab = .help
            default:
                selectedTab = .feeds
            }
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: PreferencesTab) -> some View {
        let isSelected = selectedTab == tab

        if #available(macOS 26.0, *) {
            PreferencesTabButton(tab: tab, isSelected: isSelected) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = tab
                    preferencesTab = tabPreferenceKey(tab)
                }
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = tab
                    preferencesTab = tabPreferenceKey(tab)
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20))
                    Text(tab.title)
                        .font(.system(size: 11))
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 70)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                    }
                }
            )
            .opacity(isSelected ? 1.0 : 0.7)
        }
    }

    private func tabPreferenceKey(_ tab: PreferencesTab) -> String {
        switch tab {
        case .feeds: return "feeds"
        case .filters: return "filters"
        case .settings: return "settings"
        case .help: return "help"
        }
    }
}

@available(macOS 26.0, *)
struct PreferencesTabButton: View {
    let tab: PreferencesView.PreferencesTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(width: 70)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(0.08))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Feeds Tab

struct FeedsTabView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @State private var newFeedURL: String = ""
    @State private var selectedFeed: Feed?
    @State private var showingAddSheet: Bool = false
    @State private var showingSuggestedFeeds: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedFeed) {
                ForEach(store.feeds) { feed in
                    HStack(spacing: 8) {
                        FeedIconView(iconURL: feed.iconURL, feedURL: feed.url, size: 16)
                        Text(feed.title)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .tag(feed)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.removeFeed(store.feeds[index])
                    }
                }
            }
            .listStyle(.inset)
            
            Divider()
            
            HStack {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(String(localized: "Add feed", bundle: .module))
                .accessibilityLabel(String(localized: "Add feed", bundle: .module))
                .keyboardShortcut("n", modifiers: [.command])
                
                Button(String(localized: "Import", bundle: .module)) {
                    importOPML()
                }
                
                Button(String(localized: "Export", bundle: .module)) {
                    exportOPML()
                }

                Button(String(localized: "Starter / Suggested Feeds", bundle: .module)) {
                    if #available(macOS 13.0, *) {
                        openWindow(id: "suggestedFeeds")
                    } else {
                        showingSuggestedFeeds = true
                    }
                }
                
                Spacer()
                
                Button {
                    if let feed = selectedFeed {
                        store.removeFeed(feed)
                        selectedFeed = nil
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedFeed == nil)
                .help(String(localized: "Remove selected feed", bundle: .module))
                .accessibilityLabel(String(localized: "Remove selected feed", bundle: .module))
                .keyboardShortcut(.delete, modifiers: [])
            }
            .padding(12)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddFeedSheet(isPresented: $showingAddSheet)
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSuggestedFeeds) {
            SuggestedFeedsSheet(isPresented: $showingSuggestedFeeds)
                .environmentObject(store)
        }
    }
    
    private func importOPML() {
        let panel = NSOpenPanel()
        let opmlType = UTType(filenameExtension: "opml") ?? .xml
        panel.allowedContentTypes = [.xml, opmlType]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                store.importOPML(from: data)
            }
        }
    }
    
    private func exportOPML() {
        let panel = NSSavePanel()
        let opmlType = UTType(filenameExtension: "opml") ?? .xml
        panel.allowedContentTypes = [opmlType]
        panel.nameFieldStringValue = "feeds.opml"
        
        if panel.runModal() == .OK, let url = panel.url {
            let opml = store.exportOPML()
            try? opml.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Suggested Feeds Sheet

struct SuggestedFeedsSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var isPresented: Bool
    var hideDoneButton: Bool = false
    @State private var selectedFeedIds: Set<String> = []
    @State private var feedbackMessage: String?
    @State private var feedbackIsError: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(String(localized: "Starter / Suggested Feeds", bundle: .module))
                    .font(.headline)
                Spacer()
                if !hideDoneButton {
                    Button(String(localized: "Done", bundle: .module)) {
                        isPresented = false
                    }
                    .keyboardShortcut(.escape)
                }
            }
            
            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(feedbackIsError ? .red : .secondary)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SuggestedFeeds.packs) { pack in
                        suggestedPackCard(pack)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
    }
    
    private func suggestedPackCard(_ pack: SuggestedFeedPack) -> some View {
        let selectedInPack = selectedFeeds(in: pack)
        let hasAddableFeeds = pack.feeds.contains { !isFeedAlreadyAdded($0) }
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(pack.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(String(localized: "Add All", bundle: .module)) {
                    addFeeds(pack.feeds, packTitle: pack.title)
                }
                .disabled(!hasAddableFeeds)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(pack.feeds) { feed in
                    Toggle(isOn: Binding(
                        get: { selectedFeedIds.contains(feed.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedFeedIds.insert(feed.id)
                            } else {
                                selectedFeedIds.remove(feed.id)
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Text(feed.title)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if isFeedAlreadyAdded(feed) {
                                Text(String(localized: "Added", bundle: .module))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(isFeedAlreadyAdded(feed))
                }
            }
            
            HStack {
                Spacer()
                Button(String(localized: "Add Selected", bundle: .module)) {
                    addFeeds(selectedInPack, packTitle: pack.title)
                }
                .disabled(selectedInPack.isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }
    
    private func selectedFeeds(in pack: SuggestedFeedPack) -> [SuggestedFeed] {
        pack.feeds.filter { selectedFeedIds.contains($0.id) }
    }
    
    private func isFeedAlreadyAdded(_ feed: SuggestedFeed) -> Bool {
        store.feeds.contains { $0.url.lowercased() == feed.url.lowercased() }
    }
    
    private func addFeeds(_ feeds: [SuggestedFeed], packTitle: String) {
        guard !feeds.isEmpty else { return }
        let addedCount = store.addSuggestedFeeds(feeds)
        feedbackIsError = addedCount == 0
        if addedCount == 0 {
            feedbackMessage = String(format: String(localized: "All feeds in %@ are already added.", bundle: .module), packTitle)
        } else {
            feedbackMessage = String(format: String(localized: "Added %lld feed(s) from %@.", bundle: .module), addedCount, packTitle)
        }
        removeSelectedAlreadyAdded()
    }
    
    private func removeSelectedAlreadyAdded() {
        selectedFeedIds = selectedFeedIds.filter { id in
            !store.feeds.contains { $0.url.lowercased() == id }
        }
    }
}

// MARK: - Filters Tab

struct FiltersTabView: View {
    @EnvironmentObject private var store: FeedStore
    @State private var selectedRule: FilterRule?
    @State private var showingRuleEditor = false
    @State private var editingRule: FilterRule?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Toggle("", isOn: $store.smartFiltersEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text(String(localized: "Enable rules", bundle: .module))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Rules list
            if store.filterRules.isEmpty {
                emptyState
            } else {
                rulesList
            }
            
            Divider()
            
            // Bottom toolbar
            HStack {
                Button {
                    editingRule = nil
                    showingRuleEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(String(localized: "Add filter rule", bundle: .module))
                .accessibilityLabel(String(localized: "Add filter rule", bundle: .module))
                
                if let rule = selectedRule {
                    Button {
                        editingRule = rule
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help(String(localized: "Edit selected rule", bundle: .module))
                    .accessibilityLabel(String(localized: "Edit selected rule", bundle: .module))
                    
                    Button {
                        store.deleteFilterRule(rule)
                        selectedRule = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(String(localized: "Delete selected rule", bundle: .module))
                    .accessibilityLabel(String(localized: "Delete selected rule", bundle: .module))
                }
                
                Spacer()
                
                if store.smartFiltersEnabled && !store.filterRules.isEmpty {
                    Text(String(format: String(localized: "%lld active", bundle: .module), store.filterRules.filter { $0.isEnabled }.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(rule: rule)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorView(rule: nil)
                .environmentObject(store)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(String(localized: "No filter rules yet", bundle: .module))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                exampleRow(icon: "highlighter", color: .orange, text: String(localized: "Highlight articles about \"Swift\"", bundle: .module))
                exampleRow(icon: "eye.slash", color: .gray, text: String(localized: "Hide items containing \"sponsored\"", bundle: .module))
                exampleRow(icon: "star.fill", color: .yellow, text: String(localized: "Auto-star posts from favorite feeds", bundle: .module))
            }
            .padding(.vertical, 8)
            
            Button(String(localized: "Create First Rule", bundle: .module)) {
                editingRule = nil
                showingRuleEditor = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    private func exampleRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
    
    private var rulesList: some View {
        List(selection: $selectedRule) {
            ForEach(store.filterRules) { rule in
                RuleRowView(rule: rule)
                    .tag(rule)
                    .contextMenu {
                        Button(String(localized: "Edit", bundle: .module)) {
                            editingRule = rule
                        }
                        Button(rule.isEnabled ? String(localized: "Disable", bundle: .module) : String(localized: "Enable", bundle: .module)) {
                            store.toggleFilterRule(rule)
                        }
                        Divider()
                        Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                            store.deleteFilterRule(rule)
                            if selectedRule?.id == rule.id {
                                selectedRule = nil
                            }
                        }
                    }
            }
        }
        .listStyle(.inset)
    }
}

struct RuleRowView: View {
    let rule: FilterRule
    @EnvironmentObject private var store: FeedStore
    
    var body: some View {
        HStack(spacing: 10) {
            // Indicator based on action type
            Group {
                if rule.action == .highlight {
                    Circle()
                        .fill(rule.effectiveColor)
                        .frame(width: 12, height: 12)
                } else if rule.action == .addIcon, let emoji = rule.iconEmoji {
                    Text(emoji)
                        .font(.system(size: 12))
                        .frame(height: 12)
                } else {
                    Image(systemName: rule.action.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                
                Text(ruleDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in store.toggleFilterRule(rule) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }
    
    private var ruleDescription: String {
        let conditionCount = rule.conditions.count
        let conditionText = conditionCount == 1 ? String(localized: "1 condition", bundle: .module) : String(format: String(localized: "%lld conditions", bundle: .module), conditionCount)
        let feedText = rule.feedScope.isAllFeeds ? String(localized: "All feeds", bundle: .module) : String(format: String(localized: "%lld feeds", bundle: .module), rule.feedScope.selectedFeedIds.count)
        return "\(rule.action.rawValue) • \(conditionText) • \(feedText)"
    }
}

// MARK: - Rule Editor

struct RuleEditorView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var action: FilterAction
    @State private var logic: FilterLogic
    @State private var conditions: [FilterCondition]
    @State private var highlightColor: HighlightColor
    @State private var customColor: Color
    @State private var iconEmoji: String
    @State private var isEnabled: Bool
    @State private var applyToAllFeeds: Bool
    @State private var selectedFeedIds: Set<UUID>
    @State private var showingColorPicker = false
    @State private var showingFeedSelector = false
    @State private var hexInput: String = ""
    
    private let existingRule: FilterRule?
    private var isEditing: Bool { existingRule != nil }
    
    private let commonEmojis = ["⭐", "🔥", "💡", "📌", "🎯", "✅", "❗", "🚀"]
    
    init(rule: FilterRule?) {
        self.existingRule = rule
        
        if let rule = rule {
            _name = State(initialValue: rule.name)
            _action = State(initialValue: rule.action)
            _logic = State(initialValue: rule.logic)
            _conditions = State(initialValue: rule.conditions)
            _highlightColor = State(initialValue: rule.highlightColor)
            _customColor = State(initialValue: rule.highlightColor == .custom ? Color(hex: rule.customColorHex ?? "007AFF") : .blue)
            _iconEmoji = State(initialValue: rule.iconEmoji ?? "⭐")
            _isEnabled = State(initialValue: rule.isEnabled)
            _applyToAllFeeds = State(initialValue: rule.feedScope.isAllFeeds)
            _selectedFeedIds = State(initialValue: Set(rule.feedScope.selectedFeedIds))
        } else {
            _name = State(initialValue: "")
            _action = State(initialValue: .highlight)
            _logic = State(initialValue: .any)
            _conditions = State(initialValue: [FilterCondition()])
            _highlightColor = State(initialValue: .blue)
            _customColor = State(initialValue: .blue)
            _iconEmoji = State(initialValue: "⭐")
            _isEnabled = State(initialValue: true)
            _applyToAllFeeds = State(initialValue: true)
            _selectedFeedIds = State(initialValue: [])
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? String(localized: "Edit Rule", bundle: .module) : String(localized: "New Rule", bundle: .module))
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Rule name
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Name", bundle: .module))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        FocusableTextField(text: $name, placeholder: String(localized: "e.g., Highlight Swift articles", bundle: .module), shouldFocus: false)
                            .frame(height: 22)
                    }
                    
                    // Feed scope - button to show multi-select sheet
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Apply to", bundle: .module))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Button {
                            showingFeedSelector = true
                        } label: {
                            HStack {
                                Text(feedScopeLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider()
                    
                    // Action picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Action", bundle: .module))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Picker("", selection: $action) {
                            ForEach(FilterAction.allCases, id: \.self) { actionOption in
                                Label(actionOption.rawValue, systemImage: actionOption.icon)
                                    .tag(actionOption)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        
                        Text(action.localizedDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    
                    // Color picker (only for highlight)
                    if action == .highlight {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Background Color", bundle: .module))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 8) {
                                ForEach(HighlightColor.presetCases, id: \.self) { color in
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            if highlightColor == color {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .onTapGesture {
                                            highlightColor = color
                                        }
                                }
                                
                                // Custom color picker - multi-color gradient icon
                                Button {
                                    showingColorPicker = true
                                } label: {
                                    if highlightColor == .custom {
                                        Circle()
                                            .fill(customColor)
                                            .frame(width: 24, height: 24)
                                            .overlay {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                    } else {
                                        // Multi-color gradient icon
                                        Circle()
                                            .fill(
                                                AngularGradient(
                                                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                                    center: .center
                                                )
                                            )
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showingColorPicker) {
                                    VStack(spacing: 12) {
                                        Text(String(localized: "Choose Custom Color", bundle: .module))
                                            .font(.system(size: 12, weight: .medium))
                                        
                                        // Show current color
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(customColor)
                                            .frame(width: 150, height: 40)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                                            }
                                        
                                        // Hex code input
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(String(localized: "Hex Code", bundle: .module))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                            HStack {
                                                Text("#")
                                                    .foregroundStyle(.secondary)
                                                FocusableTextField(text: $hexInput, placeholder: String(localized: "e.g. FF5733", bundle: .module), shouldFocus: false)
                                                    .frame(width: 100, height: 22)
                                                    .onChange(of: hexInput) { _, newValue in
                                                        if newValue.count == 6 {
                                                            customColor = Color(hex: newValue)
                                                            highlightColor = .custom
                                                        }
                                                    }
                                            }
                                        }
                                        
                                        Button(String(localized: "Done", bundle: .module)) {
                                            showingColorPicker = false
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                    .padding()
                                    .frame(width: 220)
                                }
                                .onAppear {
                                    hexInput = customColor.toHex()
                                }
                            }
                        }
                    }
                    
                    // Emoji picker (only for addIcon)
                    if action == .addIcon {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Icon", bundle: .module))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 6) {
                                ForEach(commonEmojis, id: \.self) { emoji in
                                    Text(emoji)
                                        .font(.system(size: 18))
                                        .frame(width: 28, height: 28)
                                        .background(iconEmoji == emoji ? Color.blue.opacity(0.2) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .onTapGesture {
                                            iconEmoji = emoji
                                        }
                                }
                            }
                            
                            HStack {
                                Text(String(localized: "Or type custom:", bundle: .module))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                FocusableTextField(text: $iconEmoji, placeholder: "", shouldFocus: false)
                                    .frame(width: 50, height: 22)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Conditions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "When", bundle: .module))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Picker("", selection: $logic) {
                                ForEach(FilterLogic.allCases, id: \.self) { logicOption in
                                    Text(logicOption.rawValue).tag(logicOption)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                            
                            Text(logic.localizedDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        ForEach($conditions) { $condition in
                            ConditionRow(condition: $condition) {
                                if conditions.count > 1 {
                                    conditions.removeAll { $0.id == condition.id }
                                }
                            }
                        }
                        
                        Button {
                            conditions.append(FilterCondition())
                        } label: {
                            Label(String(localized: "Add Condition", bundle: .module), systemImage: "plus.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button(String(localized: "Cancel", bundle: .module)) {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(isEditing ? String(localized: "Save", bundle: .module) : String(localized: "Add Rule", bundle: .module)) {
                    saveRule()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 420, height: 540)
        .sheet(isPresented: $showingFeedSelector) {
            FeedSelectorSheet(
                applyToAllFeeds: $applyToAllFeeds,
                selectedFeedIds: $selectedFeedIds,
                isPresented: $showingFeedSelector
            )
            .environmentObject(store)
        }
        .onAppear {
            // CRITICAL: Change activation policy to allow keyboard input in sheets
            // LSUIElement apps need this to receive keyboard events
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            // Only restore LSUIElement behavior if no other regular windows are open
            // (e.g., if Preferences window is still open, keep .regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let hasVisibleWindows = NSApp.windows.contains { window in
                    window.isVisible && 
                    window.level == .normal && 
                    !window.className.contains("Sheet") &&
                    window.identifier?.rawValue != "addFeed"
                }
                
                if !hasVisibleWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
    
    private var isValid: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasConditions = conditions.contains { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        let hasFeedScope = applyToAllFeeds || !selectedFeedIds.isEmpty
        return hasName && hasConditions && hasFeedScope
    }
    
    private var feedScopeLabel: String {
        if applyToAllFeeds {
            return String(localized: "All feeds", bundle: .module)
        } else if selectedFeedIds.isEmpty {
            return String(localized: "Select feeds", bundle: .module)
        } else if selectedFeedIds.count == 1 {
            let feedId = selectedFeedIds.first!
            return store.feeds.first { $0.id == feedId }?.title ?? String(localized: "1 feed", bundle: .module)
        } else {
            return String(format: String(localized: "%lld feeds", bundle: .module), selectedFeedIds.count)
        }
    }
    
    private func saveRule() {
        // Filter out empty conditions
        let validConditions = conditions.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        
        guard !validConditions.isEmpty else { return }
        
        let feedScope: FeedScope = applyToAllFeeds ? .allFeeds : .specificFeeds(Array(selectedFeedIds))
        
        let rule = FilterRule(
            id: existingRule?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            isEnabled: isEnabled,
            action: action,
            conditions: validConditions,
            logic: logic,
            highlightColor: highlightColor,
            customColorHex: highlightColor == .custom ? customColor.toHex() : nil,
            iconEmoji: action == .addIcon ? iconEmoji : nil,
            feedScope: feedScope
        )
        
        if isEditing {
            store.updateFilterRule(rule)
        } else {
            store.addFilterRule(rule)
        }
        
        dismiss()
    }
}

struct ConditionRow: View {
    @Binding var condition: FilterCondition
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $condition.field) {
                ForEach(FilterField.allCases, id: \.self) { field in
                    Label(field.rawValue, systemImage: field.icon)
                        .tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            
            Picker("", selection: $condition.comparison) {
                ForEach(FilterComparison.allCases, id: \.self) { comparison in
                    Text(comparison.rawValue).tag(comparison)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            
            FocusableTextField(text: $condition.value, placeholder: String(localized: "value", bundle: .module), shouldFocus: false)
                .frame(height: 22)
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove condition", bundle: .module))
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Feed Selector Sheet

struct FeedSelectorSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var applyToAllFeeds: Bool
    @Binding var selectedFeedIds: Set<UUID>
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "Select Feeds", bundle: .module))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Done", bundle: .module)) {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            // List of feeds
            List {
                // All Feeds option
                Toggle(isOn: $applyToAllFeeds) {
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        Text(String(localized: "All feeds", bundle: .module))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .toggleStyle(.checkbox)
                .onChange(of: applyToAllFeeds) { _, newValue in
                    if newValue {
                        selectedFeedIds.removeAll()
                    }
                }
                
                Divider()
                
                // Individual feeds
                ForEach(store.feeds) { feed in
                    Toggle(isOn: Binding(
                        get: { selectedFeedIds.contains(feed.id) },
                        set: { isSelected in
                            if isSelected {
                                applyToAllFeeds = false
                                selectedFeedIds.insert(feed.id)
                            } else {
                                selectedFeedIds.remove(feed.id)
                            }
                        }
                    )) {
                        HStack {
                            FeedIconView(iconURL: feed.iconURL, feedURL: feed.url, size: 14)
                            Text(feed.title)
                                .font(.system(size: 13))
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(applyToAllFeeds)
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 350, height: 400)
    }
}

// MARK: - RSS Feed Discovery

struct DiscoveredFeed: Identifiable {
    let id = UUID()
    let url: String
    let title: String?
    let type: String
}

final class FeedDiscovery {
    static func discoverFeeds(from urlString: String) async -> [DiscoveredFeed] {
        // First check if it's already an RSS/Atom feed URL
        if urlString.contains("/feed") || urlString.contains("/rss") || urlString.contains(".xml") || urlString.contains(".atom") {
            return []
        }

        guard let url = URL(string: urlString) else { return [] }

        do {
            let request = URLRequest(url: url, timeoutInterval: defaultRequestTimeout)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return [] }

            return parseHTMLForFeeds(html: html, baseURL: url)
        } catch {
            return []
        }
    }

    private static func parseHTMLForFeeds(html: String, baseURL: URL) -> [DiscoveredFeed] {
        var feeds: [DiscoveredFeed] = []

        // Look for <link> tags with RSS/Atom feeds using regex
        let linkPattern = #/<link[^>]+rel=["']alternate["'][^>]+type=["'](application/rss\+xml|application/atom\+xml)["'][^>]*>/#
        let matches = html.matches(of: linkPattern)

        for match in matches {
            let linkTag = String(match.output.0)

            // Extract href using regex
            let hrefPattern = #/href=["']([^"']+)["']/#
            if let hrefMatch = linkTag.firstMatch(of: hrefPattern) {
                let hrefString = String(hrefMatch.output.1)

                // Extract title if present
                var title: String?
                let titlePattern = #/title=["']([^"']+)["']/#
                if let titleMatch = linkTag.firstMatch(of: titlePattern) {
                    title = String(titleMatch.output.1)
                }

                // Extract type
                var feedType = "RSS"
                if linkTag.contains("atom") {
                    feedType = "Atom"
                }

                // Make absolute URL if relative
                let absoluteURL: String
                if hrefString.hasPrefix("http") {
                    absoluteURL = hrefString
                } else if hrefString.hasPrefix("/") {
                    absoluteURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(hrefString)"
                } else {
                    absoluteURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")/\(hrefString)"
                }

                feeds.append(DiscoveredFeed(url: absoluteURL, title: title, type: feedType))
            }
        }

        // Also check common feed URLs as fallback
        if feeds.isEmpty {
            let commonPaths = ["/feed", "/rss", "/atom.xml", "/feed.xml", "/rss.xml", "/index.xml"]
            for path in commonPaths {
                let feedURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(path)"
                feeds.append(DiscoveredFeed(url: feedURL, title: nil, type: "RSS"))
            }
        }

        return feeds
    }
}

// MARK: - Add Feed Window (standalone window wrapper)

struct AddFeedWindow: View {
    @EnvironmentObject private var store: FeedStore
    @State private var isSheetPresented = true
    
    var body: some View {
        AddFeedSheet(isPresented: $isSheetPresented)
            .environmentObject(store)
            .onChange(of: isSheetPresented) { _, newValue in
                if !newValue {
                    // Sheet was dismissed, close the window
                    DispatchQueue.main.async {
                        // Try multiple ways to find and close the window
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" }) {
                            window.close()
                        } else if let window = NSApp.windows.first(where: { $0.title == "Add Feed" }) {
                            window.close()
                        } else {
                            // Fallback: close the key window if it looks like our add feed window
                            if let keyWindow = NSApp.keyWindow, keyWindow.level == .floating {
                                keyWindow.close()
                            }
                        }
                    }
                }
            }
            .frame(width: 350)
            .onAppear {
                // Reset state when window opens
                isSheetPresented = true
                
                // Configure window for proper input handling
                DispatchQueue.main.async {
                    configureAddFeedWindow()
                }
            }
    }
    
    private func configureAddFeedWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" || $0.title == "Add Feed" }) else { return }
        
        // Set identifier if not set
        if window.identifier == nil {
            window.identifier = NSUserInterfaceItemIdentifier("addFeed")
        }
        
        // CRITICAL: Temporarily change activation policy to allow keyboard input
        // LSUIElement apps can't receive keyboard events without this
        NSApp.setActivationPolicy(.regular)
        
        // Make it a floating panel
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.moveToActiveSpace)
        
        // Ensure it can become key and accept input
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Restore LSUIElement behavior when window closes
        // Using unique name to avoid duplicate observers
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Add Feed Sheet

struct AddFeedSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var isPresented: Bool
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    @State private var errorMessage: String?
    @State private var isDiscovering: Bool = false
    @State private var discoveredFeeds: [DiscoveredFeed] = []
    @State private var selectedDiscoveredFeed: DiscoveredFeed?

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Add Feed", bundle: .module))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Feed URL", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    FocusableTextField(text: $feedURL, placeholder: String(localized: "https://example.com/feed.xml", bundle: .module), shouldFocus: true)
                        .frame(height: 22)
                        .onChange(of: feedURL) { oldValue, newValue in
                            // Auto-detect feeds when URL changes
                            if newValue != oldValue && !newValue.isEmpty {
                                Task {
                                    await detectFeeds(from: newValue)
                                }
                            }
                        }

                    if isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                }

                // Show discovered feeds
                if !discoveredFeeds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Found RSS feeds:", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(discoveredFeeds.prefix(5)) { feed in
                            HStack(spacing: 6) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    if let title = feed.title {
                                        Text(title)
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    Text(feed.url)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button(String(localized: "Use", bundle: .module)) {
                                    feedURL = feed.url
                                    if let title = feed.title, feedTitle.isEmpty {
                                        feedTitle = title
                                    }
                                    discoveredFeeds = []
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                    Text(String(localized: "Title (optional)", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                FocusableTextField(text: $feedTitle, placeholder: String(localized: "My Feed", bundle: .module), shouldFocus: false)
                    .frame(height: 22)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }

            HStack {
                Button(String(localized: "Cancel", bundle: .module)) {
                    // Reset state and close
                    errorMessage = nil
                    isDiscovering = false
                    discoveredFeeds = []
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                if #available(macOS 26.0, *) {
                    Button(String(localized: "Add", bundle: .module)) {
                        addFeed()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscovering)
                } else {
                    Button(String(localized: "Add", bundle: .module)) {
                        addFeed()
                    }
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscovering)
                }
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            // CRITICAL: Change activation policy to allow keyboard input in sheets
            // LSUIElement apps need this to receive keyboard events
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            // Only restore LSUIElement behavior if no other regular windows are open
            // (e.g., if Preferences window is still open, keep .regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let hasVisibleWindows = NSApp.windows.contains { window in
                    window.isVisible && 
                    window.level == .normal && 
                    !window.className.contains("Sheet") &&
                    window.identifier?.rawValue != "addFeed"
                }
                
                if !hasVisibleWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private func detectFeeds(from urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only try to discover if it looks like a website URL
        guard trimmed.hasPrefix("http") && !trimmed.contains("/feed") && !trimmed.contains(".xml") else {
            return
        }

        isDiscovering = true
        discoveredFeeds = []

        let feeds = await FeedDiscovery.discoverFeeds(from: trimmed)

        await MainActor.run {
            isDiscovering = false
            discoveredFeeds = feeds
        }
    }

    private func addFeed() {
        errorMessage = nil

        let cleanURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            errorMessage = String(localized: "This feed is already added.", bundle: .module)
            return
        }

        // Show loading state and validate feed
        isDiscovering = true
        Task {
            let result = await store.addFeed(url: feedURL, title: feedTitle.isEmpty ? nil : feedTitle)
            await MainActor.run {
                isDiscovering = false
                if result.success {
                    isPresented = false
                } else {
                    errorMessage = result.errorMessage
                }
            }
        }
    }
}

// MARK: - Focusable TextField (AppKit wrapper for reliable focus)

// Custom NSTextField that handles tab properly in sheets
class SheetTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Ensure text editing starts immediately
            selectText(nil)
        }
        return result
    }
    
    // CRITICAL: Override to prevent key events from being swallowed
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle tab key within the sheet context
        if event.keyCode == 48 { // Tab key
            if event.modifierFlags.contains(.shift) {
                // Shift-Tab: move to previous control
                if let window = self.window {
                    window.selectPreviousKeyView(nil)
                }
                return true
            } else {
                // Tab: move to next control
                if let window = self.window {
                    window.selectNextKeyView(nil)
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var shouldFocus: Bool
    
    func makeNSView(context: Context) -> SheetTextField {
        let textField = SheetTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 13)
        textField.focusRingType = .exterior
        return textField
    }
    
    func updateNSView(_ nsView: SheetTextField, context: Context) {
        // Only update if the value actually changed and we're not currently editing
        // This prevents the text field from resetting while the user is typing
        if nsView.stringValue != text && nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
        
        if shouldFocus && !context.coordinator.hasFocused {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                    context.coordinator.hasFocused = true
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        var hasFocused = false
        
        init(_ parent: FocusableTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @EnvironmentObject private var store: FeedStore
    @AppStorage("rssLaunchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("rssStickyWindow") private var stickyWindow: Bool = true
    @State private var installedBrowsers: [BrowserInfo] = []
    @State private var previousLanguage: String = ""
    @State private var showRestartAlert = false
    
    var body: some View {
        Form {
            // General Settings
            Section(header: Text(String(localized: "General", bundle: .module))) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Language", bundle: .module))
                        Text(String(localized: "Requires app restart", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $store.selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language.rawValue)
                        }
                    }
                    .frame(width: 150)
                    .onChange(of: store.selectedLanguage) { oldValue, newValue in
                        if !previousLanguage.isEmpty && oldValue != newValue {
                            showRestartAlert = true
                        }
                    }
                }
                
                HStack {
                    Text(String(localized: "Appearance", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.appearanceMode) {
                        Text(String(localized: "System", bundle: .module)).tag("system")
                        Text(String(localized: "Light", bundle: .module)).tag("light")
                        Text(String(localized: "Dark", bundle: .module)).tag("dark")
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text(String(localized: "Browser", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.selectedBrowser) {
                        ForEach(installedBrowsers) { browser in
                            Text(browser.name).tag(browser.path)
                        }
                    }
                    .frame(width: 200)
                }
                
                Toggle(String(localized: "Show Unread Badge", bundle: .module), isOn: $store.showUnreadBadge)
                Toggle(String(localized: "Notify on New Items", bundle: .module), isOn: $store.newItemNotificationsEnabled)
                Toggle(String(localized: "Sticky Window", bundle: .module), isOn: $stickyWindow)
                Toggle(String(localized: "Launch at Login", bundle: .module), isOn: $launchAtLogin)
            }
            
            // RSS Appearance Settings
            Section(header: Text(String(localized: "RSS Appearance", bundle: .module))) {
                HStack {
                    Text(String(localized: "Font Size", bundle: .module))
                    Spacer()
                    Slider(value: $store.fontSize, in: 10...18, step: 1) {
                        Text(String(localized: "Font Size", bundle: .module))
                    }
                    .frame(width: 150)
                    Text("\(Int(store.fontSize))pt")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(String(localized: "Title Max Lines", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.titleMaxLines) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .frame(width: 100)
                }
                
                Toggle(String(localized: "Show Summary", bundle: .module), isOn: $store.showSummaryGlobal)
                Toggle(String(localized: "Show Feed Icons", bundle: .module), isOn: $store.showFeedIcons)
                Toggle(String(localized: "Hide Read Items", bundle: .module), isOn: $store.hideReadItems)
            }
            
            // Feed Settings
            Section(header: Text(String(localized: "Feed Settings", bundle: .module))) {
                HStack {
                    Text(String(localized: "Max Items per Feed", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.maxItemsPerFeed) {
                        Text("25").tag(25)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("200").tag(200)
                    }
                    .frame(width: 100)
                }
                
                HStack {
                    Text(String(localized: "Refresh Interval", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.refreshIntervalMinutes) {
                        Text(String(localized: "Manual", bundle: .module)).tag(0)
                        Text(String(localized: "5 min", bundle: .module)).tag(5)
                        Text(String(localized: "15 min", bundle: .module)).tag(15)
                        Text(String(localized: "30 min", bundle: .module)).tag(30)
                        Text(String(localized: "1 hour", bundle: .module)).tag(60)
                        Text(String(localized: "2 hours", bundle: .module)).tag(120)
                    }
                    .frame(width: 120)
                    .onChange(of: store.refreshIntervalMinutes) { _, _ in
                        store.startRefreshTimer()
                    }
                }
                
                HStack {
                    Text(String(localized: "Time Format", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.timeFormat) {
                        Text(String(localized: "12-hour", bundle: .module)).tag("12h")
                        Text(String(localized: "24-hour", bundle: .module)).tag("24h")
                    }
                    .frame(width: 120)
                }
            }
            
            // Danger Zone
            Section {
                HStack {
                    Button(String(localized: "Quit App", bundle: .module)) {
                        NSApplication.shared.terminate(nil)
                    }
                    
                    Spacer()
                    
                    Button(String(localized: "Clear All Data", bundle: .module)) {
                        store.clearItems()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            installedBrowsers = BrowserInfo.getInstalledBrowsers()
            previousLanguage = store.selectedLanguage
        }
        .alert(String(localized: "Restart Required", bundle: .module), isPresented: $showRestartAlert) {
            Button(String(localized: "OK", bundle: .module), role: .cancel) { }
            Button(String(localized: "Quit Now", bundle: .module)) {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text(String(localized: "Please quit and restart the app for the language change to take effect.", bundle: .module))
        }
    }
}

// MARK: - Help Tab

struct HelpTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    helpItem(
                        icon: "newspaper",
                        title: String(localized: "Reading Articles", bundle: .module),
                        description: String(localized: "Click on an article to open it in your browser and mark it as read.", bundle: .module)
                    )
                    
                    helpItem(
                        icon: "star",
                        title: String(localized: "Starring Items", bundle: .module),
                        description: String(localized: "Right-click an article and select 'Star' to save it for later.", bundle: .module)
                    )
                    
                    helpItem(
                        icon: "arrow.clockwise",
                        title: String(localized: "Refreshing Feeds", bundle: .module),
                        description: String(localized: "Press ⌘R or click the refresh button to fetch new articles.", bundle: .module)
                    )
                    
                    helpItem(
                        icon: "link",
                        title: String(localized: "Adding Feeds", bundle: .module),
                        description: String(localized: "Go to Feeds tab and click + to add a new RSS feed URL, or use Starter / Suggested Feeds for packs.", bundle: .module)
                    )
                    
                    helpItem(
                        icon: "square.and.arrow.up",
                        title: String(localized: "Import/Export", bundle: .module),
                        description: String(localized: "Use OPML files to import or export your feed subscriptions.", bundle: .module)
                    )
                    
                    helpItem(
                        icon: "line.3.horizontal.decrease.circle",
                        title: String(localized: "Smart Filters", bundle: .module),
                        description: String(localized: "Create rules in the Filters tab to automatically highlight, hide, star, or add icons to articles based on title, content, author, URL, or category. Combine conditions with 'All' or 'Any' logic.", bundle: .module)
                    )
                }
                
                Divider()
                
                Text(String(localized: "Keyboard Shortcuts", bundle: .module))
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("⌘R", String(localized: "Refresh feeds", bundle: .module))
                    shortcutRow("⌘,", String(localized: "Open preferences", bundle: .module))
                    shortcutRow("⌘Q", String(localized: "Quit app", bundle: .module))
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func helpItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
