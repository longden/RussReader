# RussReader

A lightweight macOS menu bar RSS reader built with SwiftUI.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)

## Features

- **Menu Bar Integration** - Lives in your menu bar with unread count badge
- **Multiple Feeds** - Subscribe to unlimited RSS/Atom feeds
- **Smart Filters** - Rule-based filters: highlight, hide, auto-star, notify, and more
- **Article Preview** - Inline article preview pane with HTML rendering
- **Authenticated Feeds** - Basic Auth and Bearer Token support via Keychain
- **OPML Support** - Import and export your subscriptions (including CSV)
- **Suggested Feeds** - Curated feed packs across news, tech, AI, and more
- **Localization** - Multi-language support with per-language preference
- **Customizable** - Font size, colors, refresh interval
- **Keyboard Shortcuts** - ⌘R (refresh), ⌘, (preferences), ⌘Q (quit)

## Installation

### Option 1: Download Release (Recommended)

1. Download the latest `RussReader-X.X.X.dmg` from [Releases](https://github.com/longden/russreader/releases)
2. Open the DMG file
3. Drag "RussReader" to your Applications folder
4. Launch from Applications or Spotlight

### Option 2: Build from Source

#### Development Build (Fast)
```bash
./RussReader/scripts/build-debug.sh
open "RussReader/.build/debug/RussReader.app"
```

#### Production Build (One Command)
```bash
./RussReader/scripts/build-release.sh
# Creates: RussReader/.build/release/RussReader-1.0.0.dmg
```

This single command builds, strips symbols, and creates a distributable DMG.

## Usage

1. Click the newspaper icon in your menu bar
2. Add feeds via Preferences (⌘,) → Feeds → "+"
3. Click articles to open in browser
4. Right-click to star or mark as read/unread

## Suggested Feeds

The app includes curated feed packs to get started:
- General News (BBC, Reuters)
- AI & Tech Blogs (Simon Willison, GitHub, OpenAI)
- iOS / macOS (Swift by Sundell, Hacking with Swift, SwiftLee)
- Cybersecurity, Machine Learning, React, Startups, Product Management

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

### Future Distribution Channels
- **App Store**: Planned for future release
- **Homebrew**: Planned via `brew install russreader`

## Version

Current version: **1.0.0**

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT License - see [LICENSE](LICENSE) for details
