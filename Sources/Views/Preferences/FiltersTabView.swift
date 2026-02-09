import SwiftUI
import AppKit

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
                if store.smartFiltersEnabled && !store.filterRules.isEmpty {
                    Text(String(format: String(localized: "%lld active", bundle: .module), store.filterRules.filter { $0.isEnabled }.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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
                }
                
                Spacer()
                
                if let rule = selectedRule {
                    Button {
                        store.deleteFilterRule(rule)
                        selectedRule = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(String(localized: "Delete selected rule", bundle: .module))
                    .accessibilityLabel(String(localized: "Delete selected rule", bundle: .module))
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
