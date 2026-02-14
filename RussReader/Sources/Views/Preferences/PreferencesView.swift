import SwiftUI
import AppKit

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
            case .feeds: return String(localized: "Feeds")
            case .filters: return String(localized: "Filters")
            case .settings: return String(localized: "Settings")
            case .help: return String(localized: "Help")
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
                Text(String(localized: "Preferences"))
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
            
            // Ensure preferences window stays in front for LSUIElement apps
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" || $0.title == "Preferences" }) {
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
        .onDisappear {
            // Restore LSUIElement behavior when preferences closes
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
