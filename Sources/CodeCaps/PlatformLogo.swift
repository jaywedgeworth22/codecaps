import AppKit
import SwiftUI

/// How a provider's brand mark should be drawn.
///
/// - `standard` keeps the mark's own brand colors (orange for OpenAI, blue for
///   Cursor, etc.).  Reads loudest on the menu bar, and is what every other
///   consumer of these icons ships by default.
/// - `template` keeps only the silhouette; the foreground color takes over, so
///   the same image is legible on Light and Dark surfaces and against any
///   menu bar tint.
/// - `custom` shows a user-supplied image (PNG, SVG, or PDF) chosen from
///   Settings → Platforms → ⋯ → Logo Style → Custom.
public enum MarkStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case template
    case custom

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .standard:  return "Standard"
        case .template:  return "Light/Dark"
        case .custom:   return "Custom"
        }
    }
}

/// Displays the provider mark bundled with the menu bar application.
///
/// The provider key is the canonical key used by QuotaCore.  Unknown keys
/// deliberately use a neutral SF Symbol instead of guessing at a brand.
public struct PlatformLogo: View {
    public let providerKey: String
    public let size: CGFloat
    public let style: MarkStyle
    public let tint: Color?

    public init(providerKey: String,
                size: CGFloat = 22,
                style: MarkStyle = .template,
                tint: Color? = nil) {
        self.providerKey = providerKey
        self.size = size
        self.style = style
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let image = PlatformLogoImage.load(providerKey: providerKey, style: style) {
                Image(nsImage: image)
                    .renderingMode(style == .standard ? .original : .template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tint ?? Theme.ink)
            } else {
                Image(systemName: PlatformLogoImage.fallbackSymbolName(for: providerKey))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

public enum PlatformLogoImage {
    /// Cached standard (full-color) marks, keyed by provider key.
    private static let standardCache = NSCache<NSString, NSImage>()
    /// Cached template (monochrome) marks, keyed by provider key.
    private static let templateCache = NSCache<NSString, NSImage>()
    /// Cached menu-bar renders, keyed by `<providerKey>|<style>`.
    private static let menuBarCache = NSCache<NSString, NSImage>()

    /// Filesystem location for user-supplied custom logos.  Created on first
    /// save so the OS shows it in Finder without a separate call.
    public static let customMarksDirectory: URL = {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport
            .appendingPathComponent("CodeCaps", isDirectory: true)
            .appendingPathComponent("CustomMarks", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private static let resourceNames: [String: (name: String, ext: String)] = [
        "anthropic": ("claude", "svg"),
        "claude": ("claude", "svg"),
        "openai": ("openai", "svg"),
        "codex": ("openai", "svg"),
        "google-antigravity": ("gemini", "svg"),
        "antigravity": ("gemini", "svg"),
        "gemini": ("gemini", "svg"),
        "xai": ("grok", "svg"),
        "grok": ("grok", "svg"),
        "grok-cli": ("grok", "svg"),
        "grok-bot": ("grok-bot", "svg"),
        "minimax": ("minimax", "svg"),
        "cursor": ("cursor", "svg"),
    ]

    /// Return the bundled asset for `providerKey`, or `nil` if no artwork ships.
    /// The standard cache preserves brand colors; the template cache marks the
    /// image as a template so it adapts to Light/Dark and menu bar selection.
    private static func bundledImage(providerKey: String, style: MarkStyle = .template) -> NSImage? {
        let key = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() as NSString
        let cache = (style == .standard) ? standardCache : templateCache
        if let cached = cache.object(forKey: key) { return cached }
        guard let resource = resourceNames[key as String],
              let url = Bundle.module.url(forResource: resource.name, withExtension: resource.ext)
                  ?? Bundle.module.url(
                      forResource: resource.name,
                      withExtension: resource.ext,
                      subdirectory: "ProviderMarks"
                  ),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        // Keep the brand color cached separately from the template copy.
        let colorCopy = NSImage(contentsOf: url)
        if (key as String) == "grok-bot" {
            // Grok Bot is monochrome; adapt to Light and Dark mode across all styles.
            colorCopy?.isTemplate = true
        } else {
            colorCopy?.isTemplate = false
        }
        standardCache.setObject(colorCopy ?? image, forKey: key)
        let templateCopy = NSImage(contentsOf: url)
        templateCopy?.isTemplate = true
        templateCache.setObject(templateCopy ?? image, forKey: key)
        return cache.object(forKey: key)
    }

    /// Return a mark for `providerKey` honoring `style`.  Custom marks are
    /// resolved relative to `customMarksDirectory`; an unreadable file falls
    /// back to the bundled asset so a stale selection does not blank the menu
    /// bar.
    public static func load(providerKey: String, style: MarkStyle) -> NSImage? {
        let key = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch style {
        case .standard:
            return bundledImage(providerKey: key, style: .standard)
        case .template:
            return bundledImage(providerKey: key, style: .template)
        case .custom:
            if let custom = loadCustom(providerKey: key) { return custom }
            return bundledImage(providerKey: key, style: .standard)
        }
    }

    /// The on-disk path for a provider's custom mark, or `nil` if none has been
    /// chosen yet.  Exposed so Settings can show the path and offer Remove.
    public static func customMarkURL(providerKey: String) -> URL? {
        let key = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for ext in ["svg", "png", "pdf"] {
            let url = customMarksDirectory.appendingPathComponent("\(key).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Copy `source` into `customMarksDirectory` as `<key>.<ext>`, removing any
    /// older variant first so an owner swapping a PNG for an SVG never ends up
    /// with two files and the wrong one cached.  Returns the new on-disk URL,
    /// or `nil` if the source could not be read.
    @discardableResult
    public static func importCustomMark(from source: URL, providerKey: String) -> URL? {
        let key = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ext = source.pathExtension.lowercased()
        guard ["svg", "png", "pdf"].contains(ext) else { return nil }
        guard let data = try? Data(contentsOf: source) else { return nil }
        // Drop any older variant (PNG/SVG/PDF) so the menu bar never caches the
        // wrong one.
        for old in ["svg", "png", "pdf"] {
            let url = customMarksDirectory.appendingPathComponent("\(key).\(old)")
            try? FileManager.default.removeItem(at: url)
        }
        let destination = customMarksDirectory.appendingPathComponent("\(key).\(ext)")
        do {
            try data.write(to: destination, options: [.atomic])
        } catch {
            return nil
        }
        // Bust the menu-bar render cache so the new file shows on the next draw.
        for style in MarkStyle.allCases {
            menuBarCache.removeObject(forKey: "\(key)|\(style.rawValue)" as NSString)
        }
        return destination
    }

    /// Remove the custom mark for `providerKey`, if any.
    public static func removeCustomMark(providerKey: String) {
        let key = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for ext in ["svg", "png", "pdf"] {
            let url = customMarksDirectory.appendingPathComponent("\(key).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
        for style in MarkStyle.allCases {
            menuBarCache.removeObject(forKey: "\(key)|\(style.rawValue)" as NSString)
        }
    }

    private static func loadCustom(providerKey: String) -> NSImage? {
        guard let url = customMarkURL(providerKey: providerKey) else { return nil }
        return NSImage(contentsOf: url)
    }

    public static func menuBarImage(providerKey: String, size: CGFloat = 16, style: MarkStyle = .template) -> NSImage? {
        let key = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(key)|\(style.rawValue)" as NSString
        if let cached = menuBarCache.object(forKey: cacheKey) { return cached }
        guard let original = load(providerKey: key, style: style) else {
            return nil
        }
        let targetSize = NSSize(width: size, height: size)
        let img = NSImage(size: targetSize)
        img.lockFocus()
        original.draw(in: NSRect(origin: .zero, size: targetSize),
                      from: NSRect(origin: .zero, size: original.size),
                      operation: .copy,
                      fraction: 1.0)
        img.unlockFocus()
        img.isTemplate = (style == .template)
        menuBarCache.setObject(img, forKey: cacheKey)
        return img
    }

    public static func fallbackSymbolName(for providerKey: String) -> String {
        let key = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "anthropic", "claude": return "sparkles"
        case "openai", "codex": return "cpu"
        case "google-antigravity", "antigravity", "gemini": return "sparkle"
        case "xai", "grok", "grok-cli": return "bolt"
        case "grok-bot": return "bolt.badge.a"
        case "minimax": return "m.square"
        case "cursor": return "cursorarrow.rays"
        default: return "gauge.with.dots.needle.50percent"
        }
    }
}
