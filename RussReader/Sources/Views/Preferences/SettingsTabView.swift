import SwiftUI
import AppKit

// MARK: - Settings Tab

struct SettingsTabView: View {
    @EnvironmentObject private var store: FeedStore
    @AppStorage("rssLaunchAtLogin") private var launchAtLogin: Bool = false
    @State private var installedBrowsers: [BrowserInfo] = []
    @State private var previousLanguage: String = ""
    @State private var showRestartAlert = false
    
    var body: some View {
        Form {
            // General
            Section(header: Text(String(localized: "General"))) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Language"))
                        Text(String(localized: "Requires app restart"))
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
                    Text(String(localized: "Appearance"))
                    Spacer()
                    Picker("", selection: $store.appearanceMode) {
                        Text(String(localized: "System")).tag("system")
                        Text(String(localized: "Light")).tag("light")
                        Text(String(localized: "Dark")).tag("dark")
                    }
                    .frame(width: 120)
                }
                
                Toggle(String(localized: "Launch at Login"), isOn: $launchAtLogin)
            }
            
            // Reading
            Section(header: Text(String(localized: "Behavior"))) {
                HStack {
                    Text(String(localized: "Article Open"))
                    Spacer()
                    Picker("", selection: $store.openInPreview) {
                        Text(String(localized: "In App Preview")).tag(true)
                        Text(String(localized: "Open in Browser")).tag(false)
                    }
                    .frame(width: 200)
                }
                
                HStack {
                    Text(String(localized: "Browser"))
                    Spacer()
                    Picker("", selection: $store.selectedBrowser) {
                        ForEach(installedBrowsers) { browser in
                            Text(browser.name).tag(browser.path)
                        }
                    }
                    .frame(width: 250)
                }
                
                Toggle(String(localized: "Show unread count in menubar"), isOn: $store.showUnreadBadge)
                Toggle(String(localized: "Send notification on new item"), isOn: $store.newItemNotificationsEnabled)
                    .disabled(!store.notificationsAvailable)
                
                if !store.notificationsAvailable {
                    Text(String(localized: "Notifications require the .app bundle (use build script instead of swift run)"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                HStack {
                    Text(String(localized: "Refresh Interval"))
                    Spacer()
                    Picker("", selection: $store.refreshIntervalMinutes) {
                        Text(String(localized: "Manual")).tag(0)
                        Text(String(localized: "5 min")).tag(5)
                        Text(String(localized: "15 min")).tag(15)
                        Text(String(localized: "30 min")).tag(30)
                        Text(String(localized: "1 hour")).tag(60)
                        Text(String(localized: "2 hours")).tag(120)
                        Text(String(localized: "3 hours")).tag(180)
                    }
                    .frame(width: 120)
                    .onChange(of: store.refreshIntervalMinutes) { _, _ in
                        store.startRefreshTimer()
                    }
                }
                
                HStack {
                    Text(String(localized: "Max Items per Feed"))
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
            
            // Appearance
            Section(header: Text(String(localized: "Appearance"))) {
                HStack {
                    Text(String(localized: "Window Width"))
                    Spacer()
                    Picker("", selection: $store.windowWidthSize) {
                        Text(String(localized: "Small")).tag("small")
                        Text(String(localized: "Medium")).tag("medium")
                        Text(String(localized: "Large")).tag("large")
                        Text(String(localized: "X-Large")).tag("xlarge")
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text(String(localized: "Window Height"))
                    Spacer()
                    Picker("", selection: $store.windowHeightSize) {
                        Text(String(localized: "Small")).tag("small")
                        Text(String(localized: "Medium")).tag("medium")
                        Text(String(localized: "Large")).tag("large")
                        Text(String(localized: "X-Large")).tag("xlarge")
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text(String(localized: "Font Size"))
                    Spacer()
                    Slider(value: $store.fontSize, in: 10...18, step: 1) {
                        Text(String(localized: "Font Size"))
                    }
                    .frame(width: 150)
                    Text("\(Int(store.fontSize))pt")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(String(localized: "RSS Title Max Lines"))
                    Spacer()
                    Picker("", selection: $store.titleMaxLines) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .frame(width: 100)
                }
                
                HStack {
                    Text(String(localized: "Time Format"))
                    Spacer()
                    Picker("", selection: $store.timeFormat) {
                        Text(String(localized: "12-hour")).tag("12h")
                        Text(String(localized: "24-hour")).tag("24h")
                    }
                    .frame(width: 120)
                }
                
                Toggle(String(localized: "RSS Item Summary"), isOn: $store.showSummaryGlobal)
                Toggle(String(localized: "Show Feed Icons"), isOn: $store.showFeedIcons)
                Toggle(String(localized: "Show \"via Feed\" Source"), isOn: $store.showViaFeed)
            }
            
            // Actions
            Section(header: Text(String(localized: "Actions"))) {
                HStack {
                    Button(String(localized: "Quit App")) {
                        NSApplication.shared.terminate(nil)
                    }
                    
                    Spacer()
                    
                    Button(String(localized: "Clear All Data")) {
                        store.clearItems()
                    }
                    .foregroundStyle(.red)
                }
            }
            
            // Debug
            Section(header: Text(String(localized: "Debug"))) {
                Button(String(localized: "Show Onboarding Again")) {
                    UserDefaults.standard.set(false, forKey: "rssOnboardingComplete")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            installedBrowsers = BrowserInfo.getInstalledBrowsers()
            previousLanguage = store.selectedLanguage
        }
        .alert(String(localized: "Restart Required"), isPresented: $showRestartAlert) {
            Button(String(localized: "OK"), role: .cancel) { }
            Button(String(localized: "Quit Now")) {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text(String(localized: "Please quit and restart the app for the language change to take effect."))
        }
    }
}
