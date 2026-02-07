import SwiftUI
import AppKit

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
                    Text(String(localized: "Window Width", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.windowWidthSize) {
                        Text(String(localized: "Small", bundle: .module)).tag("small")
                        Text(String(localized: "Medium", bundle: .module)).tag("medium")
                        Text(String(localized: "Large", bundle: .module)).tag("large")
                        Text(String(localized: "X-Large", bundle: .module)).tag("xlarge")
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text(String(localized: "Window Height", bundle: .module))
                    Spacer()
                    Picker("", selection: $store.windowHeightSize) {
                        Text(String(localized: "Small", bundle: .module)).tag("small")
                        Text(String(localized: "Medium", bundle: .module)).tag("medium")
                        Text(String(localized: "Large", bundle: .module)).tag("large")
                        Text(String(localized: "X-Large", bundle: .module)).tag("xlarge")
                    }
                    .frame(width: 120)
                }
                
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
