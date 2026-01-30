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

## Building & Running

### Quick Start (Swift Package Manager)

```bash
# Build and run
swift build && .build/debug/RSSReader

# Or just build
swift build

# Build for release
swift build -c release
```

### Using Xcode

1. Open the project folder in Xcode
2. Select "My Mac" as the run destination
3. Press ⌘R to build and run

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
- Xcode 15+ (for building)

## License

MIT License
