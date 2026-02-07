# Views Architecture

The Views.swift file has been refactored from a monolithic 2053-line file into a well-organized, modular structure following modern SwiftUI best practices.

## Directory Structure

```
Sources/
  Views/
    RSSReaderView.swift              # Main menu bar content view (531 lines)
    FeedItemRow.swift                # Individual feed item row component
    ArticlePreviewPane.swift         # Article detail/preview view (900 lines)
    
    Components/
      FilterTabButton.swift          # Filter tab button (macOS 26+)
      RefreshButton.swift            # Refresh button with rotation animation
      FooterGlassButton.swift        # Footer button (macOS 26+)
    
    ViewModifiers/
      GlassEffectModifiers.swift     # Glass effect modifiers (macOS 26+)
      ButtonStyleModifiers.swift     # Button styling and interactions
      ContextMenuModifiers.swift     # Context menus and utilities
    
    Utilities/
      ColorExtensions.swift          # Color utility extensions
      NSViewRepresentables.swift     # AppKit integration wrappers
      WindowHelpers.swift            # Window management functions
  
  Views.swift                        # Main entry point (minimal)
```

## Benefits of This Architecture

### 1. **Single Responsibility**
Each file contains one primary view, component, or set of related modifiers. This makes code easier to understand, test, and maintain.

### 2. **Improved Compile Times**
Smaller files with focused functionality compile faster. The Swift type checker can process each file independently without hitting complexity limits.

### 3. **Better Code Navigation**
Developers can quickly find what they need:
- Need to modify the refresh button? → `Components/RefreshButton.swift`
- Working on glass effects? → `ViewModifiers/GlassEffectModifiers.swift`
- Fixing context menu behavior? → `ViewModifiers/ContextMenuModifiers.swift`

### 4. **Easier Testing**
Components are isolated and can be tested independently. Mock dependencies are simpler when files are focused.

### 5. **Team Collaboration**
Multiple developers can work on different components simultaneously with minimal merge conflicts.

### 6. **Clear Dependencies**
Import statements at the top of each file make dependencies explicit and easy to audit.

## File Descriptions

### Main Views

**RSSReaderView.swift** (531 lines)
- Primary menu bar content view
- Manages feed item list, filters, and navigation
- Integrates article preview pane

**FeedItemRow.swift** (168 lines)
- Individual feed item row display
- Shows title, description, feed info, date, indicators
- Handles hover states and preview button

**ArticlePreviewPane.swift** (900 lines)
- Full article preview/detail view
- HTML content parsing and rendering
- Content blocks (text, images, code, tables, etc.)
- Toolbar with read/star/share actions

### Components

**FilterTabButton.swift**
- Reusable filter tab button with glass effect
- Used for All/Unread/Starred filters
- macOS 26+ only

**RefreshButton.swift**
- Refresh button with animated rotation
- Uses TimelineView for smooth animation
- Handles hover states

**FooterGlassButton.swift**
- Generic footer button with glass effect
- Used for settings, preferences, etc.
- macOS 26+ only

### View Modifiers

**GlassEffectModifiers.swift**
- GlassCapsule: Capsule-shaped glass container
- CapsuleGlassModifier: Glass effect for capsule shapes
- BadgeGlassModifier: Badge styling with glass
- RefreshButtonGlassModifier: Glass effect for refresh button
- All macOS 26+ with fallbacks

**ButtonStyleModifiers.swift**
- HeaderButtonStyle: Header button styling with glass hover
- HeaderButtonHoverModifier: Hover effects for buttons
- View extensions: headerButtonStyle(), pointerOnHover()

**ContextMenuModifiers.swift**
- FeedItemContextMenu: Context menu for feed items (mark read/starred, share, copy)
- SectionDivider: Divider line with customizable alignment
- View extensions: feedItemContextMenu(), sectionDivider()

### Utilities

**ColorExtensions.swift**
- Color(hex:): Initialize from hex string
- Color(nsColor:): Initialize from NSColor
- toHex(): Convert to hex string

**NSViewRepresentables.swift**
- MenuBarWindowConfigurator: Configure menu bar window properties
- VisualEffectBackground: NSVisualEffectView wrapper
- AppearanceApplier: Apply light/dark appearance

**WindowHelpers.swift**
- openPreferencesWindow(): Open/focus preferences window
- openAddFeedWindow(): Open/focus add feed window
- Handles LSUIElement app activation

## Migration Notes

### Backward Compatibility
The Views.swift entry point remains for backward compatibility. All components are accessible throughout the module without additional imports.

### Import Requirements
Each file includes only the imports it needs:
- SwiftUI (all files)
- AppKit (for NSWorkspace, NSColor, etc.)
- SwiftSoup (ArticlePreviewPane only)

### Availability Annotations
Components using macOS 26+ features (glass effects) are properly marked with `@available(macOS 26.0, *)` and include fallbacks for older versions.

## Future Improvements

1. **Extract ArticlePreviewPane Components**
   - The 900-line ArticlePreviewPane could be further split into:
     - ContentBlockRenderer.swift (rendering logic)
     - PreviewToolbar.swift (toolbar component)
     - ContentParser.swift (HTML parsing logic)

2. **Shared Theme System**
   - Create a Theme/ directory with centralized spacing, colors, fonts

3. **Component Library**
   - Build a reusable component library with documentation

4. **Unit Tests**
   - Add tests for individual components and modifiers

## Maintenance Guidelines

1. **Keep Files Focused**: Each file should have one clear purpose
2. **Limit File Size**: Aim for < 300 lines; split if larger
3. **Use Clear Names**: File names should match primary struct/class
4. **Document Public APIs**: Add doc comments for public components
5. **Version Compatibility**: Always provide fallbacks for macOS 26+ features
