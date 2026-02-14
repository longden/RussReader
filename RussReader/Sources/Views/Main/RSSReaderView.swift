//
//  RussReaderView.swift
//  RussReader
//
//  Main menu bar content view
//

import SwiftUI
import AppKit

struct RussReaderView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredItemId: UUID?
    @State private var selectedItemId: UUID?
    @State private var showingFeedPicker: Bool = false
    @State private var hoveredPickerFeedId: UUID?
    @State private var feedPickerHovered: Bool = false
    @State private var previewingItem: FeedItem? = nil
    @AppStorage("rssPreferencesTab") private var preferencesTab: String = "feeds"
    @AppStorage("rssOnboardingComplete") private var onboardingComplete: Bool = false

    @ViewBuilder
    var body: some View {
        if !onboardingComplete {
            OnboardingView()
                .environmentObject(store)
        } else {
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
                
                if store.showingError, let errorMessage = store.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { store.showingError = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
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
                .modifier(WindowStyleModifier(style: store.windowStyle))
                .background(MenuBarWindowConfigurator())
                .background(AppearanceApplier(appearanceMode: store.appearanceMode))
                .frame(width: store.windowWidth, height: store.windowHeight)
        } else {
            content
                .background(backgroundVisualEffect)
                .background(MenuBarWindowConfigurator())
                .background(AppearanceApplier(appearanceMode: store.appearanceMode))
                .frame(width: store.windowWidth, height: store.windowHeight)
        }
        } // else onboardingComplete
    }

    // MARK: - Background Styles
    
    @available(macOS 26.0, *)
    private struct WindowStyleModifier: ViewModifier {
        let style: String
        
        func body(content: Content) -> some View {
            switch style {
            case "translucent":
                content.background(.ultraThinMaterial)
            case "frosted":
                content.background(.thinMaterial)
            default:
                content.background(.regularMaterial)
            }
        }
    }
    
    private var backgroundVisualEffect: some View {
        switch store.windowStyle {
        case "translucent":
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
        case "frosted":
            VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow)
        default:
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredItems) { item in
                        FeedItemRow(
                            item: item,
                            feedTitle: store.feedTitle(for: item),
                            feedIconURL: store.feedIconURL(for: item),
                            feedURL: store.feedURL(for: item),
                            feedId: store.feedId(for: item),
                            feedAuthType: store.feedAuthType(for: item),
                            isHovered: hoveredItemId == item.id,
                            fontSize: store.fontSize,
                            titleMaxLines: store.titleMaxLines,
                            timeFormat: store.timeFormat,
                            highlightColor: store.highlightColor(for: item),
                            iconEmoji: store.iconEmoji(for: item),
                            showSummary: store.shouldShowSummary(for: item),
                            showFeedIcon: store.showFeedIcons,
                            showViaFeed: store.showViaFeed,
                            openInPreview: store.openInPreview,
                            onPreview: {
                                store.markAsRead(item)
                                if store.openInPreview {
                                    withAnimation(.easeInOut(duration: 0.2)) { previewingItem = item }
                                } else {
                                    store.openItem(item)
                                }
                            }
                        )
                        .id(item.id)
                        .background(selectedItemId == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .onTapGesture {
                            selectedItemId = item.id
                            if store.openInPreview {
                                store.markAsRead(item)
                                withAnimation(.easeInOut(duration: 0.2)) { previewingItem = item }
                            } else {
                                store.openItem(item)
                            }
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
            .onAppear {
                if let id = selectedItemId {
                    DispatchQueue.main.async {
                        proxy.scrollTo(id, anchor: .center)
                        selectedItemId = nil
                    }
                }
            }
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
        if store.openInPreview {
            store.markAsRead(item)
            withAnimation(.easeInOut(duration: 0.2)) { previewingItem = item }
        } else {
            store.openItem(item)
        }
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

