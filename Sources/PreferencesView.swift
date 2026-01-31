import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Preferences View

struct PreferencesView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PreferencesTab = .feeds
    
    enum PreferencesTab: String, CaseIterable {
        case feeds = "Feeds"
        case settings = "Settings"
        case help = "Help"
        
        var icon: String {
            switch self {
            case .feeds: return "link"
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

            HStack(spacing: 24) {
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
        .frame(width: 400, height: 450)
        .environmentObject(store)
    }

    private func tabButton(_ tab: PreferencesTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
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
            .foregroundStyle(isSelected ? .blue : .secondary)
            .frame(width: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    HStack {
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

// MARK: - Add Feed Sheet

struct AddFeedSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var isPresented: Bool
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    @FocusState private var isURLFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Feed")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Feed URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/feed.xml", text: $feedURL)
                    .textFieldStyle(.roundedBorder)
                    .focused($isURLFocused)
                
                Text("Title (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("My Feed", text: $feedTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add") {
                    store.addFeed(url: feedURL, title: feedTitle.isEmpty ? nil : feedTitle)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            isURLFocused = true
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
