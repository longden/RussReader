import SwiftUI
import AppKit

// MARK: - Network Constants

let defaultRequestTimeout: TimeInterval = 15

// MARK: - Favicon Cache

final class FaviconCache {
    static let shared = FaviconCache()
    
    private let cache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL?
    private var inFlightURLs = Set<String>()
    private let lock = NSLock()
    
    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 10 * 1024 * 1024 // 10 MB
        
        // Set up disk cache directory
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let faviconDir = cachesDir.appendingPathComponent("FaviconCache", isDirectory: true)
            try? fileManager.createDirectory(at: faviconDir, withIntermediateDirectories: true)
            cacheDirectory = faviconDir
        } else {
            cacheDirectory = nil
        }
    }
    
    func image(for url: URL) -> NSImage? {
        let key = url.absoluteString as NSString
        
        // Check memory cache
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        // Check disk cache
        if let diskImage = loadFromDisk(for: url) {
            cache.setObject(diskImage, forKey: key)
            return diskImage
        }
        
        return nil
    }
    
    func store(_ image: NSImage, for url: URL) {
        let key = url.absoluteString as NSString
        cache.setObject(image, forKey: key)
        saveToDisk(image, for: url)
    }
    
    func beginFetch(for url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = url.absoluteString
        if inFlightURLs.contains(key) { return false }
        inFlightURLs.insert(key)
        return true
    }
    
    func endFetch(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        inFlightURLs.remove(url.absoluteString)
    }
    
    private func cacheFileURL(for url: URL) -> URL? {
        guard let cacheDirectory = cacheDirectory else { return nil }
        let filename = url.absoluteString.data(using: .utf8)?.base64EncodedString() ?? url.lastPathComponent
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    private func loadFromDisk(for url: URL) -> NSImage? {
        guard let fileURL = cacheFileURL(for: url),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }
    
    private func saveToDisk(_ image: NSImage, for url: URL) {
        guard let fileURL = cacheFileURL(for: url),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: fileURL)
    }
}

// MARK: - Feed Icon View

struct FeedIconView: View {
    let iconURL: String?
    let feedURL: String?
    let size: CGFloat
    
    @State private var image: NSImage?
    
    init(iconURL: String?, feedURL: String? = nil, size: CGFloat = 16) {
        self.iconURL = iconURL
        self.feedURL = feedURL
        self.size = size
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: iconURL ?? feedURL) {
            await loadIcon()
        }
    }
    
    private func loadIcon() async {
        guard image == nil else { return }
        
        // Try the feed-provided icon URL first
        if let iconURL = iconURL, let url = URL(string: iconURL) {
            if let loadedImage = await loadImageWithCache(from: url) {
                await MainActor.run { self.image = loadedImage }
                return
            }
        }
        
        // Fall back to favicon from the website
        if let feedURL = feedURL,
           let feedUrl = URL(string: feedURL),
           let host = feedUrl.host,
           let faviconURL = URL(string: "https://\(host)/favicon.ico") {
            if let loadedImage = await loadImageWithCache(from: faviconURL) {
                await MainActor.run { self.image = loadedImage }
            }
        }
    }
    
    private func loadImageWithCache(from url: URL) async -> NSImage? {
        if let cached = FaviconCache.shared.image(for: url) {
            return cached
        }
        
        guard FaviconCache.shared.beginFetch(for: url) else { return nil }
        defer { FaviconCache.shared.endFetch(for: url) }
        
        do {
            let request = URLRequest(url: url, timeoutInterval: defaultRequestTimeout)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = NSImage(data: data) {
                FaviconCache.shared.store(image, for: url)
                return image
            }
        } catch {
            // Silently fail - icon loading is non-critical
        }
        return nil
    }
}

// MARK: - Focusable TextField (AppKit wrapper for reliable focus)

class SheetTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            selectText(nil)
        }
        return result
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 48 { // Tab key
            if event.modifierFlags.contains(.shift) {
                if let window = self.window {
                    window.selectPreviousKeyView(nil)
                }
                return true
            } else {
                if let window = self.window {
                    window.selectNextKeyView(nil)
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var shouldFocus: Bool
    
    func makeNSView(context: Context) -> SheetTextField {
        let textField = SheetTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 13)
        textField.focusRingType = .exterior
        return textField
    }
    
    func updateNSView(_ nsView: SheetTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        if shouldFocus && !context.coordinator.hasFocused {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                    context.coordinator.hasFocused = true
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        var hasFocused = false
        
        init(_ parent: FocusableTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

// MARK: - Browser Detection

struct BrowserInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    
    static func getInstalledBrowsers() -> [BrowserInfo] {
        var browsers: [BrowserInfo] = []
        var seenPaths = Set<String>()
        
        if let defaultBrowserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://")!) {
            let defaultName = defaultBrowserURL.deletingPathExtension().lastPathComponent
            browsers.append(BrowserInfo(
                id: "default",
                name: "System Default (\(defaultName))",
                path: "default"
            ))
            seenPaths.insert("default")
        } else {
            browsers.append(BrowserInfo(
                id: "default",
                name: "System Default",
                path: "default"
            ))
            seenPaths.insert("default")
        }
        
        if let httpURL = URL(string: "https://www.example.com"),
           let browserURLs = LSCopyApplicationURLsForURL(httpURL as CFURL, .all)?.takeRetainedValue() as? [URL] {
            
            for appURL in browserURLs {
                let appPath = appURL.path
                guard !seenPaths.contains(appPath) else { continue }
                
                var appName = appURL.deletingPathExtension().lastPathComponent
                
                if let bundle = Bundle(url: appURL),
                   let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? 
                                     bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                    appName = displayName
                }
                
                browsers.append(BrowserInfo(
                    id: appPath,
                    name: appName,
                    path: appPath
                ))
                seenPaths.insert(appPath)
            }
        }
        
        return browsers
    }
}
