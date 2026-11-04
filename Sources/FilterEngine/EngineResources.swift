import Foundation

/// Anchor so `Bundle(for:)` resolves to the FilterEngine bundle inside the app.
final class ResourceAnchor: NSObject {}

public enum EngineResources {
    public static func text(name: String, ext: String) -> String? {
        let bundles = candidateBundles()
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: ext),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    public static func bundledConfig() -> SelectorConfig {
        if let text = text(name: "selectors", ext: "json"),
           let data = text.data(using: .utf8),
           let config = try? SelectorConfigValidator.validate(data) {
            return config
        }
        return .fallback
    }

    public static func hideCSS() -> String {
        text(name: "hide", ext: "css") ?? HideCSS.fallback
    }

    public static func filterScript() -> String {
        text(name: "filter", ext: "js") ?? ""
    }

    private static func candidateBundles() -> [Bundle] {
        #if SWIFT_PACKAGE
        return [Bundle.module, Bundle(for: ResourceAnchor.self)]
        #else
        return [Bundle(for: ResourceAnchor.self), Bundle.main]
        #endif
    }
}

public enum HideCSS {
    public static let fallback = """
    .enough-hidden,
    .enough-seen,
    .enough-route-hidden {
      display: none !important;
    }

    html, body {
      -webkit-text-size-adjust: 100%;
      -webkit-touch-callout: none;
    }

    body {
      -webkit-user-select: none;
    }

    input, textarea, [contenteditable="true"] {
      -webkit-user-select: text;
      -webkit-touch-callout: default;
    }

    html.enough-hide-reels[data-enough-route="reels"] article:not(.enough-keep),
    html.enough-hide-explore[data-enough-route="explore"] article:not(.enough-keep) {
      display: none !important;
    }

    /* App-install prompts. A link inside an ad (.enough-keep) stays visible. */
    a[href^="instagram:"],
    a[href*="apps.apple.com"],
    a[href*="itunes.apple.com"],
    a[href*="itms-apps"] {
      display: none !important;
    }

    .enough-keep a[href^="instagram:"],
    .enough-keep a[href*="apps.apple.com"],
    .enough-keep a[href*="itunes.apple.com"],
    .enough-keep a[href*="itms-apps"],
    a[href^="instagram:"].enough-keep,
    a[href*="apps.apple.com"].enough-keep,
    a[href*="itunes.apple.com"].enough-keep,
    a[href*="itms-apps"].enough-keep {
      display: revert !important;
    }
    """
}

public struct BootPayload: Codable, Equatable {
    public var config: SelectorConfig
    public var toggles: BootToggles
    public var css: String
    /// Shortcodes already shown on this device. Used only to collapse those posts.
    public var seen: [String]
    public var homeURL: String
    /// True only in the Personal build, and only for a platform that asked for it.
    public var hideSponsored: Bool

    public init(
        config: SelectorConfig,
        toggles: BootToggles,
        css: String,
        seen: [String] = [],
        homeURL: String = PlatformCatalog.active.homeURL.absoluteString,
        hideSponsored: Bool = PlatformCatalog.active.hidesAds
    ) {
        self.config = config
        self.toggles = toggles
        self.css = css
        self.seen = seen
        self.homeURL = homeURL
        self.hideSponsored = hideSponsored
    }
}

public enum WebBoot {
    /// Assignment injected before `filter.js`. The JSON is produced by the encoder.
    /// It is not remote code.
    public static func installationScript(
        config: SelectorConfig,
        settings: EnoughSettings,
        css: String,
        seen: [String] = [],
        homeURL: String = PlatformCatalog.active.homeURL.absoluteString,
        hideSponsored: Bool = PlatformCatalog.active.hidesAds
    ) -> String {
        let json = jsonObject(
            config: config,
            settings: settings,
            css: css,
            seen: seen,
            homeURL: homeURL,
            hideSponsored: hideSponsored
        )
        return "window.__ENOUGH_BOOT__ = \(json);"
    }

    public static func jsonObject(
        config: SelectorConfig,
        settings: EnoughSettings,
        css: String,
        seen: [String] = [],
        homeURL: String = PlatformCatalog.active.homeURL.absoluteString,
        hideSponsored: Bool = PlatformCatalog.active.hidesAds
    ) -> String {
        let payload = BootPayload(
            config: config,
            toggles: settings.bootToggles,
            css: css,
            seen: seen,
            homeURL: homeURL,
            hideSponsored: hideSponsored
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    public static func reconfigureScript(
        config: SelectorConfig,
        settings: EnoughSettings,
        css: String,
        seen: [String] = [],
        homeURL: String = PlatformCatalog.active.homeURL.absoluteString,
        hideSponsored: Bool = PlatformCatalog.active.hidesAds
    ) -> String {
        let json = jsonObject(
            config: config,
            settings: settings,
            css: css,
            seen: seen,
            homeURL: homeURL,
            hideSponsored: hideSponsored
        )
        return "window.Enough && window.Enough.reconfigure(\(json));"
    }
}

/// Mobile Safari user agent so instagram.com serves the phone site.
public enum MobileSafari {
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
}
