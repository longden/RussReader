import SwiftUI

// MARK: - Help Tab

struct HelpTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    helpItem(
                        icon: "newspaper",
                        title: String(localized: "Reading Articles"),
                        description: String(localized: "Click on an article to open it in your browser and mark it as read.")
                    )
                    
                    helpItem(
                        icon: "star",
                        title: String(localized: "Starring Items"),
                        description: String(localized: "Right-click an article and select 'Star' to save it for later.")
                    )
                    
                    helpItem(
                        icon: "arrow.clockwise",
                        title: String(localized: "Refreshing Feeds"),
                        description: String(localized: "Press ⌘R or click the refresh button to fetch new articles.")
                    )
                    
                    helpItem(
                        icon: "link",
                        title: String(localized: "Adding Feeds"),
                        description: String(localized: "Go to Feeds tab and click + to add a new RSS feed URL, or use Starter / Suggested Feeds for packs.")
                    )
                    
                    helpItem(
                        icon: "square.and.arrow.up",
                        title: String(localized: "Import/Export"),
                        description: String(localized: "Use OPML files to import or export your feed subscriptions.")
                    )
                    
                    helpItem(
                        icon: "line.3.horizontal.decrease.circle",
                        title: String(localized: "Smart Filters"),
                        description: String(localized: "Create rules in the Filters tab to automatically highlight, hide, star, or add icons to articles based on title, content, author, URL, or category. Combine conditions with 'All' or 'Any' logic.")
                    )
                }
                
                Divider()
                
                Text(String(localized: "Keyboard Shortcuts"))
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("⌘R", String(localized: "Refresh feeds"))
                    shortcutRow("⌘,", String(localized: "Open preferences"))
                    shortcutRow("⌘Q", String(localized: "Quit app"))
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
