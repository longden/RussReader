# Copilot Instructions for RSS Reader

A lightweight macOS menu bar RSS reader built with SwiftUI.

## Build Commands

### Development Build
```bash
# Fast build for testing (includes debug symbols)
./scripts/build-debug.sh
open ".build/debug/RSS Reader.app"

# Or with Swift Package Manager directly
swift build && .build/debug/RSSReader
```

### Auto-Rebuild After Changes
After making code changes, always run `swift run` to rebuild and launch the app:
```bash
swift run
```
This compiles the project and starts the app in one step. The app will appear in the menu bar.

### Production Build
```bash
# Creates stripped, signed .app bundle and DMG
./scripts/build-release.sh
# Output: .build/release/RSSReader-1.0.0.dmg
```

### Dependencies
```bash
# Resolve and download packages
swift package resolve

# Update dependencies
swift package update
```

**Note**: The project uses Swift Package Manager with FeedKit 10.0.0+ for RSS/Atom parsing.

## Architecture

### Single Source of Truth: FeedStore

The entire app state flows through **FeedStore** (`FeedStore.swift`), a `@MainActor` class that manages:
- All feeds and items as `@Published` collections
- Persistence via UserDefaults JSON encoding
- Concurrent feed fetching via structured concurrency (TaskGroup)
- Auto-refresh timer on user-configurable intervals
- Filtering (All/Unread/Starred) and item management
- OPML import/export

**Key Pattern**: FeedStore is injected via `.environmentObject()` to all views. All state mutations must go through this store.

### Concurrency Model

Network operations use `nonisolated` methods to enable parallel fetching:
```swift
// Multiple feeds fetch concurrently via TaskGroup
await withTaskGroup(of: [FeedItem].self) { group in
    for feed in feeds {
        group.addTask { await self.fetchFeedItems(feed) }
    }
}
```

Results are processed back on `@MainActor` for UI updates.

### Item Deduplication

Feed items use composite key matching to prevent duplicates on refresh:
1. RSS `<guid>` or Atom `<id>` (sourceId)
2. Link URL as fallback
3. Title + pubDate as last resort

### Persistence Keys

All data stored in UserDefaults:
- Feeds: `"rssFeeds"`
- Items: `"rssItems"`
- Settings: `@AppStorage` with `"rss"` prefix (e.g., `"rssFontSize"`, `"rssRefreshInterval"`)

### File Organization

```
Sources/
├── RSSReaderApp.swift      # App entry, MenuBarExtra, preferences window
├── FeedStore.swift         # State management, networking, persistence
├── Models.swift            # Feed, FeedItem, FeedFilter models
├── Parsers.swift           # RSSParser, OPMLParser (XMLParserDelegate)
├── Views.swift             # RSSReaderView, FeedItemRow, view modifiers
├── PreferencesView.swift   # Tabbed preferences (Feeds, Settings, Help)
└── Resources/              # AppIcon.icns, Localizable.xcstrings
```

### View Structure

**MenuBarExtra** → **RSSReaderView** (main window with filters/items list) → **FeedItemRow** (individual items)

**Preferences** window uses SwiftUI `TabView` with three tabs and `.floating` window level via `WindowAccessor` (NSViewRepresentable).

### macOS Integration

- **MenuBarExtra**: Dynamic icon (filled when unread items exist), badge with unread count
- **NSWorkspace**: Opens URLs in default browser
- **NSOpenPanel/NSSavePanel**: OPML file dialogs
- **WindowAccessor**: Sets preferences window to `.floating` level
- **OSLog**: Logging via subsystem "local.macbar" or bundle identifier

## Key Conventions

### SwiftUI + Swift Concurrency

- All view state tied to `@Published` properties in FeedStore
- Network calls are `async` and use `nonisolated` for parallelism
- Use `Task {}` blocks in SwiftUI views to bridge sync/async

### Date Parsing

Parsers support multiple RSS/Atom date formats:
- RFC822 (RSS standard)
- ISO8601 (Atom standard)
- Common variants with fallback parsing

### Error Handling

- Network errors fail silently (logged via OSLog)
- Feed fetch failures don't crash the app
- Invalid XML is skipped without user notification

### Default Content

On first launch, three default feeds are added:
1. Daring Fireball (https://daringfireball.net/feeds/main)
2. Swift by Sundell (https://www.swiftbysundell.com/rss)
3. NSHipster (https://nshipster.com/feed.xml)

## Keyboard Shortcuts

- **⌘R**: Refresh all feeds
- **⌘,**: Open preferences
- **⌘Q**: Quit app

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 5.9+
- Xcode 15+ (for building)

## Code Signing

Both build scripts use ad-hoc signing (`--sign -`) with `RSSReader.entitlements`:
- Debug: No symbol stripping
- Release: Strips symbols with `strip -x` (58% size reduction)
