# Copilot Instructions for RSS Reader

A macOS menu bar RSS reader built with SwiftUI, featuring smart filtering, authenticated feeds, rich article previews, and local notifications.

## Build Commands

### Development Build
```bash
# Fast build for testing (includes debug symbols)
./RussReader/scripts/build-debug.sh
open "RussReader/.build/debug/RussReader.app"
```

### Auto-Rebuild After Changes
After making code changes, rebuild with the debug script:
```bash
./RussReader/scripts/build-debug.sh
open "RussReader/.build/debug/RussReader.app"
```

### Production Build
```bash
# Creates stripped, signed .app bundle and DMG
./RussReader/scripts/build-release.sh
# Output: RussReader/.build/release/RussReader-1.0.0.dmg
```

### Dependencies
```bash
# Resolve Xcode-managed Swift package dependencies
xcodebuild -project RussReader.xcodeproj -resolvePackageDependencies

# Update dependencies
xcodebuild -project RussReader.xcodeproj -resolvePackageDependencies
```

**Note**: The project uses Xcode project builds with Swift Package dependencies (FeedKit 10.0.0+ and SwiftSoup 2.7.0+). Full Xcode must be selected for CLI builds.

## Architecture

### Single Source of Truth: FeedStore

The entire app state flows through **FeedStore** (`FeedStore.swift`), a `@MainActor` class that manages:
- `@Published` collections: `feeds`, `items`, `filter`, `filterRules`, `selectedFeedId`, `isRefreshing`, `lastRefreshTime`, `errorMessage`, `showingError`
- 18 `@AppStorage` user preferences (display, features, UI sizing)
- Concurrent feed fetching with HTTP eTag/Last-Modified caching and 15s timeout
- Smart filter rule engine with per-item result caching
- Local push notifications via `UNUserNotificationCenter` with custom actions
- Feed authentication (Basic Auth + Bearer Token) via Keychain
- Auto-refresh timer, OPML import/export, 30-day item retention

**Key Pattern**: FeedStore is injected via `.environmentObject()` to all views. All state mutations must go through this store.

### Data Models (Models.swift)

**Core Types:**
- `Feed`: id, title, url, eTag, lastModified, iconURL, customTitle, authType
- `FeedItem`: id, feedId, title, link, sourceId, description, contentHTML, pubDate, author, categories, isRead, isStarred, enclosures
- `Enclosure`: url, type, length (with computed `isImage`/`isAudio`/`isVideo`)
- `FeedFilter`: enum (all, unread, starred)

**Smart Filtering Types:**
- `FilterRule`: name, isEnabled, action, conditions, logic (all/any), highlightColor, iconEmoji, feedScope
- `FilterCondition`: field (title/content/author/link/category), comparison (contains/notContains/equals/startsWith/endsWith), value
- `FilterAction`: show, hide, highlight, addIcon, addSummary, autoStar, markRead, notify
- `HighlightColor`: 9 presets (blue through custom hex)
- `FilteredItemResult`: computed per-item result with visibility, highlight, icon, auto-actions, matched rules

**Other Types:**
- `AuthType`: none, basicAuth, bearerToken
- `FeedScope`: allFeeds, specificFeeds([UUID])
- `SuggestedFeed`/`SuggestedFeedPack`: curated feed collections (AI, React, startups, security, iOS, ML, products)

### Concurrency Model

Network operations use async/await for feed fetching. Results are processed on `@MainActor` for UI updates. Persistence uses deferred saves with 0.5s debounce via `DispatchQueue`.

### Caching & Performance

- In-memory filter results cache (`filterResultsCache[UUID]`)
- O(1) item lookup via `itemIndexMap()`
- Cached computed properties: `_cachedFilteredItems`, `_cachedHiddenCount`, `_cachedUnreadCount`, `_cachedStarredCount`
- HTTP-level: eTag and Last-Modified headers per feed

### Item Deduplication

Feed items use composite key matching to prevent duplicates on refresh:
1. RSS `<guid>` or Atom `<id>` (sourceId)
2. Link URL as fallback
3. Title + pubDate as last resort

### Persistence

- **UserDefaults**: Feeds (`"rssFeeds"`), Items (`"rssItems"`), Filter Rules
- **Keychain**: Feed authentication credentials (via `KeychainHelper`)
- **@AppStorage**: Settings with `"rss"` prefix (e.g., `"rssFontSize"`, `"rssRefreshInterval"`, `"rssHideReadItems"`, `"rssSmartFiltersEnabled"`)
- **Data Lifecycle**: 30-day retention, 200-item cap, `maxItemsPerFeed` truncation

### File Organization

```
RussReader/Sources/
├── App/
│   └── RSSReaderApp.swift          # App entry, MenuBarExtra windows, preferences/add-feed windows
├── Models/
│   └── Models.swift                # Feed, FeedItem, FeedFilter, FilterRule, Enclosure, SuggestedFeeds
├── Services/
│   ├── FeedStore.swift             # State management, networking, persistence, notifications
│   ├── KeychainHelper.swift        # Secure credential storage for feed authentication
│   ├── LanguageManager.swift       # Localization support
│   └── Parsers.swift               # RSSParser (FeedKit), OPMLParser (XMLParserDelegate)
├── Views/
│   ├── Main/
│   │   ├── RSSReaderView.swift     # Main menu bar window with feed list
│   │   ├── FeedItemRow.swift       # Individual feed item display
│   │   └── ArticlePreviewPane.swift # Rich HTML article preview
│   ├── AddFeed/
│   │   └── AddFeedView.swift       # Feed addition dialog with URL validation
│   ├── Onboarding/
│   │   └── OnboardingView.swift    # First-run onboarding flow
│   ├── Preferences/
│   │   ├── PreferencesView.swift   # 4-tab preferences window
│   │   ├── FeedsTabView.swift      # Feed management tab (add/remove, OPML, auth)
│   │   ├── FiltersTabView.swift    # Smart filter rules editor
│   │   ├── SettingsTabView.swift   # Appearance, display, behavior settings
│   │   └── HelpTabView.swift       # Usage instructions and shortcuts
│   ├── Components/
│   │   ├── SharedComponents.swift  # Reusable UI components
│   │   ├── FilterTabButton.swift
│   │   ├── FooterGlassButton.swift
│   │   └── RefreshButton.swift
│   └── Modifiers/
│       ├── ButtonStyleModifiers.swift
│       ├── ContextMenuModifiers.swift
│       └── GlassEffectModifiers.swift
├── Utilities/
│   ├── ColorExtensions.swift
│   ├── NSViewRepresentables.swift
│   └── WindowHelpers.swift
└── Resources/                      # Localizable.xcstrings and bundled assets
```

### View Structure

**App Windows:**
- **MenuBarExtra** (sticky + dropdown) → **RSSReaderView** → **FeedItemRow** + **ArticlePreviewPane**
- **Preferences** window: 4-tab `TabView` (Feeds, Filters, Settings, Help) with `.floating` window level
- **Add Feed** sheet: URL input with validation and auth options
- **Suggested Feeds** sheet: Curated feed packs

### macOS Integration

- **MenuBarExtra**: Dynamic icon (filled when unread), badge with unread count, sticky window mode
- **NSWorkspace**: Opens URLs in default browser
- **NSOpenPanel/NSSavePanel**: OPML file dialogs
- **WindowAccessor**: Sets window to `.floating` level (LSUIElement apps)
- **UNUserNotificationCenter**: Local notifications with Open/Mark Read/Mark All actions
- **Keychain Services**: Secure credential storage for authenticated feeds
- **Glass Effect**: macOS 26+ `.glassEffect` with fallback styling

## Key Conventions

### SwiftUI + Swift Concurrency

- All view state tied to `@Published` properties in FeedStore
- Network calls are `async`
- Use `Task {}` blocks in SwiftUI views to bridge sync/async
- Deferred saves via `DispatchQueue` with 0.5s debounce

### Parsing

- **RSS/Atom/JSON**: Via FeedKit library — extracts contentHTML, description, enclosures, author, categories
- **HTML**: SwiftSoup for stripping tags, decoding entities (capped at 100KB)
- **OPML**: Custom XMLParserDelegate for import/export
- **Date formats**: RFC822, ISO8601, and common variants with fallback

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
