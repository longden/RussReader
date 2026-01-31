import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Feed Icon View

struct FeedIconView: View {
    let iconURL: String?
    let size: CGFloat
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    init(iconURL: String?, size: CGFloat = 16) {
        self.iconURL = iconURL
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
        guard !isLoading, image == nil, let iconURL = iconURL, let url = URL(string: iconURL) else { return }
        isLoading = true
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let nsImage = NSImage(data: data) {
                await MainActor.run {
                    self.image = nsImage
                }
            }
        } catch {
            // Failed to load icon, will show default
        }
        
        isLoading = false
    }
}

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
                        FeedIconView(iconURL: feed.iconURL, size: 16)
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

// MARK: - Add Feed Sheet

struct AddFeedSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Binding var isPresented: Bool
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    
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
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                if #available(macOS 26.0, *) {
                    Button("Add") {
                        store.addFeed(url: feedURL, title: feedTitle.isEmpty ? nil : feedTitle)
                        isPresented = false
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Add") {
                        store.addFeed(url: feedURL, title: feedTitle.isEmpty ? nil : feedTitle)
                        isPresented = false
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
