import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Feeds Tab

struct FeedsTabView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.openWindow) private var openWindow
    @State private var newFeedURL: String = ""
    @State private var selectedFeed: Feed?
    @State private var showingAddSheet: Bool = false
    @State private var showingSuggestedFeeds: Bool = false
    @State private var showingNewFolder: Bool = false
    @State private var editingCredentialsFeed: Feed?
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedFeed) {
                ForEach(store.feeds) { feed in
                    feedRow(feed)
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
                
                Button(String(localized: "Import OPML", bundle: .module)) {
                    importOPML()
                }
                
                Button(String(localized: "Export OPML", bundle: .module)) {
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
        .sheet(item: $editingCredentialsFeed) { feed in
            EditCredentialsSheet(feed: feed)
                .environmentObject(store)
        }
    }
    
    private func feedRow(_ feed: Feed) -> some View {
        HStack(spacing: 8) {
            FeedIconView(iconURL: feed.iconURL, feedURL: feed.url, size: 16)
            Text(feed.title)
                .lineLimit(1)
            if feed.authType != .none {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .tag(feed)
        .contextMenu {
            Button(String(localized: "Edit Credentials…", bundle: .module)) {
                editingCredentialsFeed = feed
            }
            Button(String(localized: "Remove Feed", bundle: .module)) {
                store.removeFeed(feed)
                if selectedFeed?.id == feed.id { selectedFeed = nil }
            }
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

// MARK: - Edit Credentials Sheet

struct EditCredentialsSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    let feed: Feed
    @State private var authType: AuthType
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var token: String = ""
    
    init(feed: Feed) {
        self.feed = feed
        _authType = State(initialValue: feed.authType)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Credentials", bundle: .module))
                .font(.headline)
            
            Text(feed.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Picker(String(localized: "Authentication", bundle: .module), selection: $authType) {
                ForEach(AuthType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if authType == .basicAuth {
                TextField(String(localized: "Username", bundle: .module), text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField(String(localized: "Password", bundle: .module), text: $password)
                    .textFieldStyle(.roundedBorder)
            } else if authType == .bearerToken {
                SecureField(String(localized: "API Key or Token", bundle: .module), text: $token)
                    .textFieldStyle(.roundedBorder)
            }
            
            if authType != .none {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 9))
                    Text(String(localized: "Stored securely in Keychain. Only sent with feed requests.", bundle: .module))
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
            
            HStack {
                Button(String(localized: "Cancel", bundle: .module)) {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(String(localized: "Save", bundle: .module)) {
                    saveCredentials()
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            // Load existing credentials
            if feed.authType == .basicAuth {
                if let creds = KeychainHelper.loadBasicAuth(feedId: feed.id) {
                    username = creds.username
                    password = creds.password
                }
            } else if feed.authType == .bearerToken {
                if let creds = KeychainHelper.loadToken(feedId: feed.id) {
                    token = creds.token
                }
            }
        }
    }
    
    private func saveCredentials() {
        // Update feed auth type
        if let idx = store.feeds.firstIndex(where: { $0.id == feed.id }) {
            store.feeds[idx].authType = authType
        }
        
        // Update keychain
        KeychainHelper.deleteCredentials(feedId: feed.id)
        if authType == .basicAuth && !username.isEmpty {
            KeychainHelper.saveBasicAuth(feedId: feed.id, username: username, password: password)
        } else if authType == .bearerToken && !token.isEmpty {
            KeychainHelper.saveToken(feedId: feed.id, token: token)
        }
        
        store.save()
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
