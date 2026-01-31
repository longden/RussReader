import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        
        // Try the feed-provided icon URL first
        if let iconURL = iconURL, let url = URL(string: iconURL) {
            print("🖼️ Attempting to load feed icon from: \(iconURL)")
            if let loadedImage = await tryLoadImage(from: url) {
                await MainActor.run {
                    print("✓ Successfully loaded icon from feed")
                    self.image = loadedImage
                }
                isLoading = false
                return
            } else {
                print("✗ Failed to load icon from feed URL")
            }
        }
        
        // Fall back to favicon from the website
        if let feedURL = feedURL, let feedUrl = URL(string: feedURL) {
            // Extract domain from feed URL
            if let host = feedUrl.host {
                let faviconURL = URL(string: "https://\(host)/favicon.ico")!
                print("🖼️ Attempting to load favicon from: \(faviconURL)")
                if let loadedImage = await tryLoadImage(from: faviconURL) {
                    await MainActor.run {
                        print("✓ Successfully loaded favicon")
                        self.image = loadedImage
                    }
                } else {
                    print("✗ Failed to load favicon")
                }
            }
        }
        
        isLoading = false
    }
    
    private func tryLoadImage(from url: URL) async -> NSImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Preferences View

struct PreferencesView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PreferencesTab = .feeds
    
    enum PreferencesTab: String, CaseIterable {
        case feeds = "Feeds"
        case filters = "Filters"
        case settings = "Settings"
        case help = "Help"
        
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
                Text("Preferences")
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
    }

    @ViewBuilder
    private func tabButton(_ tab: PreferencesTab) -> some View {
        let isSelected = selectedTab == tab

        if #available(macOS 26.0, *) {
            PreferencesTabButton(tab: tab, isSelected: isSelected) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = tab
                }
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = tab
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20))
                    Text(tab.rawValue)
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
                Text(tab.rawValue)
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
    @State private var newFeedURL: String = ""
    @State private var selectedFeed: Feed?
    @State private var showingAddSheet: Bool = false
    
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
                .help("Add feed")
                
                Button("Import") {
                    importOPML()
                }
                
                Button("Export") {
                    exportOPML()
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
                .help("Remove selected feed")
            }
            .padding(12)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddFeedSheet(isPresented: $showingAddSheet)
                .environmentObject(store)
                .interactiveDismissDisabled()
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
                Text("Enable filters")
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
                .help("Add filter rule")
                
                if let rule = selectedRule {
                    Button {
                        editingRule = rule
                        showingRuleEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit selected rule")
                    
                    Button {
                        store.deleteFilterRule(rule)
                        selectedRule = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete selected rule")
                }
                
                Spacer()
                
                if store.smartFiltersEnabled && !store.filterRules.isEmpty {
                    Text("\(store.filterRules.filter { $0.isEnabled }.count) active")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorView(rule: editingRule, isPresented: $showingRuleEditor)
                .environmentObject(store)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No filter rules yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                exampleRow(icon: "highlighter", color: .orange, text: "Highlight articles about \"Swift\"")
                exampleRow(icon: "eye.slash", color: .gray, text: "Hide items containing \"sponsored\"")
                exampleRow(icon: "star.fill", color: .yellow, text: "Auto-star posts from favorite feeds")
            }
            .padding(.vertical, 8)
            
            Button("Create First Rule") {
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
                        Button("Edit") {
                            editingRule = rule
                            showingRuleEditor = true
                        }
                        Button(rule.isEnabled ? "Disable" : "Enable") {
                            store.toggleFilterRule(rule)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
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
        let conditionText = conditionCount == 1 ? "1 condition" : "\(conditionCount) conditions"
        let feedText = rule.feedScope.isAllFeeds ? "All feeds" : "\(rule.feedScope.selectedFeedIds.count) feeds"
        return "\(rule.action.rawValue) • \(conditionText) • \(feedText)"
    }
}

// MARK: - Rule Editor

struct RuleEditorView: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var isPresented: Bool
    
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
    
    private let commonEmojis = ["⭐", "🔥", "💡", "📌", "🎯", "⚡", "💎", "🚀", "📣", "🏆", "❗", "✨"]
    
    init(rule: FilterRule?, isPresented: Binding<Bool>) {
        self.existingRule = rule
        self._isPresented = isPresented
        
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
                Text(isEditing ? "Edit Rule" : "New Rule")
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
                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("e.g., Highlight Swift articles", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Feed scope - button to show multi-select sheet
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Apply to")
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
                        Text("Action")
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
                        
                        Text(action.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    
                    // Color picker (only for highlight)
                    if action == .highlight {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Background Color")
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
                                        Text("Choose Custom Color")
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
                                            Text("Hex Code")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                            HStack {
                                                Text("#")
                                                    .foregroundStyle(.secondary)
                                                TextField("e.g. FF5733", text: $hexInput)
                                                    .textFieldStyle(.roundedBorder)
                                                    .frame(width: 100)
                                                    .onChange(of: hexInput) { _, newValue in
                                                        if newValue.count == 6 {
                                                            customColor = Color(hex: newValue)
                                                            highlightColor = .custom
                                                        }
                                                    }
                                            }
                                        }
                                        
                                        Button("Done") {
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
                            Text("Icon")
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
                                Text("Or type custom:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                TextField("", text: $iconEmoji)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Conditions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("When")
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
                            
                            Text(logic.description)
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
                            Label("Add Condition", systemImage: "plus.circle")
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
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(isEditing ? "Save" : "Add Rule") {
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
            NSApp.activate(ignoringOtherApps: true)
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
            return "All Feeds"
        } else if selectedFeedIds.isEmpty {
            return "Select feeds..."
        } else if selectedFeedIds.count == 1 {
            let feedId = selectedFeedIds.first!
            return store.feeds.first { $0.id == feedId }?.title ?? "1 feed"
        } else {
            return "\(selectedFeedIds.count) feeds"
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
        
        isPresented = false
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
            
            TextField("value", text: $condition.value)
                .textFieldStyle(.roundedBorder)
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
                Text("Select Feeds")
                    .font(.headline)
                Spacer()
                Button("Done") {
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
                        Text("All Feeds")
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

// MARK: - Add Feed Sheet

struct AddFeedSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var isPresented: Bool
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Feed")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Feed URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableTextField(text: $feedURL, placeholder: "https://example.com/feed.xml", shouldFocus: true)
                    .frame(height: 22)
                
                Text("Title (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableTextField(text: $feedTitle, placeholder: "My Feed", shouldFocus: false)
                    .frame(height: 22)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                if #available(macOS 26.0, *) {
                    Button("Add") {
                        addFeed()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Add") {
                        addFeed()
                    }
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            // Activate the app to ensure keyboard focus works
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func addFeed() {
        errorMessage = nil
        
        let cleanURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.feeds.contains(where: { $0.url.lowercased() == cleanURL.lowercased() }) {
            errorMessage = "This feed is already added."
            return
        }
        
        if store.addFeed(url: feedURL, title: feedTitle.isEmpty ? nil : feedTitle) {
            isPresented = false
        }
    }
}

// MARK: - Focusable TextField (AppKit wrapper for reliable focus)

struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var shouldFocus: Bool
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 13)
        textField.focusRingType = .exterior
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
        
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
    @AppStorage("rssStickyWindow") private var stickyWindow: Bool = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Appearance")
                    Spacer()
                    Picker("", selection: $store.appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $store.fontSize, in: 10...18, step: 1) {
                        Text("Font Size")
                    }
                    .frame(width: 150)
                    Text("\(Int(store.fontSize))pt")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Max Items per Feed")
                    Spacer()
                    Picker("", selection: $store.maxItemsPerFeed) {
                        Text("25").tag(25)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("200").tag(200)
                    }
                    .frame(width: 100)
                }
            }
            
            Section {
                Toggle("Show Unread Badge", isOn: $store.showUnreadBadge)
                Toggle("Hide Read Items", isOn: $store.hideReadItems)
                Toggle("Sticky Window", isOn: $stickyWindow)
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            
            Section {
                HStack {
                    Text("Refresh Interval")
                    Spacer()
                    Picker("", selection: $store.refreshIntervalMinutes) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    .frame(width: 100)
                    .onChange(of: store.refreshIntervalMinutes) { _, _ in
                        store.startRefreshTimer()
                    }
                }
            }
            
            Section {
                HStack {
                    Button("Quit App") {
                        NSApplication.shared.terminate(nil)
                    }
                    
                    Spacer()
                    
                    Button("Clear All Data") {
                        store.items.removeAll()
                        store.save()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
                        title: "Reading Articles",
                        description: "Click on an article to open it in your browser and mark it as read."
                    )
                    
                    helpItem(
                        icon: "star",
                        title: "Starring Items",
                        description: "Right-click an article and select 'Star' to save it for later."
                    )
                    
                    helpItem(
                        icon: "arrow.clockwise",
                        title: "Refreshing Feeds",
                        description: "Press ⌘R or click the refresh button to fetch new articles."
                    )
                    
                    helpItem(
                        icon: "link",
                        title: "Adding Feeds",
                        description: "Go to Feeds tab and click + to add a new RSS feed URL."
                    )
                    
                    helpItem(
                        icon: "square.and.arrow.up",
                        title: "Import/Export",
                        description: "Use OPML files to import or export your feed subscriptions."
                    )
                }
                
                Divider()
                
                Text("Keyboard Shortcuts")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("⌘R", "Refresh feeds")
                    shortcutRow("⌘,", "Open preferences")
                    shortcutRow("⌘Q", "Quit app")
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
