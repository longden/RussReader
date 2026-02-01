# RSS Reader

A lightweight macOS menu bar RSS reader built with SwiftUI.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)

## Features

- **Menu Bar Integration** - Lives in your menu bar with unread count indicator
- **Multiple Feeds** - Subscribe to unlimited RSS/Atom feeds
- **Smart Filtering** - Filter by All, Unread, or Starred items
- **OPML Support** - Import and export your subscriptions
- **Customizable** - Adjust font size, colors, and refresh interval
- **Keyboard Shortcuts** - Quick access with ⌘R (refresh), ⌘, (preferences), ⌘Q (quit)

## Installation

### Option 1: Download Release (Recommended)

1. Download the latest `RSSReader-X.X.X.dmg` from [Releases](https://github.com/yourusername/rssreader/releases)
2. Open the DMG file
3. Drag "RSS Reader" to your Applications folder
4. Launch from Applications or Spotlight

### Option 2: Build from Source

#### Development Build (Fast)
```bash
./scripts/build-debug.sh
open ".build/debug/RSS Reader.app"
```

#### Production Build (One Command)
```bash
./scripts/build-release.sh
# Creates: .build/release/RSSReader-1.0.0.dmg
```

This single command builds, strips symbols, and creates a distributable DMG.

## Usage

1. Click the newspaper icon in your menu bar
2. Add feeds via Preferences (⌘,) → Feeds → "+"
3. Click articles to open in browser
4. Right-click to star or mark as read/unread

## Default Feeds

The app comes with sample feeds:
- Daring Fireball
- Swift by Sundell
- NSHipster

## Configuration

Access Preferences (⌘,) to configure:
- **Feeds** - Add, remove, import/export feeds
- **Settings** - Font size, colors, refresh interval
- **Help** - Keyboard shortcuts and usage tips

## Data Storage

Feeds and read states are stored in UserDefaults, persisting across launches.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ / Swift 5.9+ (for building from source)

## Distribution

### Local Sharing
Share the `.app` bundle or `.dmg` file directly with others.

**Protection**: Release builds include:
- Compiled native code (not easily reverse-engineered)
- Stripped debug symbols (58% size reduction, better obfuscation)
- Release optimizations and code signing

See [SECURITY.md](SECURITY.md) for details on code protection.

### Future Distribution Channels
- **App Store**: Planned for future release
- **Homebrew**: Planned via `brew install rssreader`

## Version

Current version: **1.0.0**

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT License - see [LICENSE](LICENSE) for details
