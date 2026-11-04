import Foundation

public struct BootToggles: Codable, Equatable {
    public var hideReels: Bool
    public var hideExplore: Bool
    public var hideSuggested: Bool

    public init(hideReels: Bool, hideExplore: Bool, hideSuggested: Bool) {
        self.hideReels = hideReels
        self.hideExplore = hideExplore
        self.hideSuggested = hideSuggested
    }
}

/// Selector document. This is data. Nothing in it is executed.
public struct SelectorConfig: Codable, Equatable {
    public var version: Int
    public var hide: HideRules
    public var posts: PostRules
    public var text: TextRules

    public struct HideRules: Codable, Equatable {
        public var reels: [String]
        public var explore: [String]
        public var suggested: [String]
        /// App-install prompts. Always applied. These are not ads.
        public var install: [String]

        public init(reels: [String], explore: [String], suggested: [String], install: [String] = []) {
            self.reels = reels
            self.explore = explore
            self.suggested = suggested
            self.install = install
        }

        private enum CodingKeys: String, CodingKey {
            case reels, explore, suggested, install
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reels = try container.decode([String].self, forKey: .reels)
            explore = try container.decode([String].self, forKey: .explore)
            suggested = try container.decode([String].self, forKey: .suggested)
            install = try container.decodeIfPresent([String].self, forKey: .install) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reels, forKey: .reels)
            try container.encode(explore, forKey: .explore)
            try container.encode(suggested, forKey: .suggested)
            try container.encode(install, forKey: .install)
        }
    }

    public struct PostRules: Codable, Equatable {
        public var containers: [String]
        public var permalink: [String]
        /// Used only to leave ads on screen and out of the count.
        public var sponsored: [String]

        public init(containers: [String], permalink: [String], sponsored: [String]) {
            self.containers = containers
            self.permalink = permalink
            self.sponsored = sponsored
        }
    }

    public struct TextRules: Codable, Equatable {
        public var suggested: [String]
        public var sponsored: [String]
        /// Exact labels on app-install buttons, such as "Open app".
        public var install: [String]

        public init(suggested: [String], sponsored: [String], install: [String] = []) {
            self.suggested = suggested
            self.sponsored = sponsored
            self.install = install
        }

        private enum CodingKeys: String, CodingKey {
            case suggested, sponsored, install
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            suggested = try container.decode([String].self, forKey: .suggested)
            sponsored = try container.decode([String].self, forKey: .sponsored)
            install = try container.decodeIfPresent([String].self, forKey: .install) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(suggested, forKey: .suggested)
            try container.encode(sponsored, forKey: .sponsored)
            try container.encode(install, forKey: .install)
        }
    }

    public init(version: Int, hide: HideRules, posts: PostRules, text: TextRules) {
        self.version = version
        self.hide = hide
        self.posts = posts
        self.text = text
    }

    public static let fallback: SelectorConfig = {
        guard let config = try? SelectorConfigValidator.validate(Data(bundledJSON.utf8)) else {
            preconditionFailure("Bundled selector JSON must validate.")
        }
        return config
    }()

    /// Kept in source so a missing bundle file still has a config, and so tests
    /// can prove the file on disk matches this document.
    public static let bundledJSON = """
    {
      "version": 1,
      "hide": {
        "reels": [
          "a[href='/reels/']",
          "a[href='/reels']",
          "a[href^='/reels/']"
        ],
        "explore": [
          "a[href='/explore/']",
          "a[href='/explore']"
        ],
        "suggested": [
          "[data-enough-suggested='1']"
        ],
        "install": [
          "a[href^='instagram:']",
          "a[href*='apps.apple.com']",
          "a[href*='itunes.apple.com']",
          "a[href*='itms-apps']"
        ]
      },
      "posts": {
        "containers": [
          "article"
        ],
        "permalink": [
          "a[href*='/p/']",
          "a[href*='/reel/']"
        ],
        "sponsored": [
          "[data-sponsored='1']",
          "[data-ad='1']",
          "a[href*='a_mpk=']"
        ]
      },
      "text": {
        "suggested": [
          "Suggested for you",
          "Suggestions for you",
          "Suggested posts"
        ],
        "sponsored": [
          "Sponsored",
          "Paid partnership",
          "Ad"
        ],
        "install": [
          "Open app",
          "Open Instagram",
          "Get the app",
          "Get Instagram",
          "Use the app",
          "Open in app",
          "Open in the app",
          "View in app"
        ]
      }
    }
    """
}

public enum SelectorConfigError: Error, Equatable {
    case invalidJSON
    case unsafeContent
    case incomplete
    case unsupportedVersion
    case tooLarge
}

public enum SelectorConfigValidator {
    public static let maxBytes = 64 * 1024
    public static let maxItemsPerList = 40
    public static let maxSelectorLength = 200
    public static let maxTextLength = 80

    public static func validate(_ data: Data) throws -> SelectorConfig {
        guard data.count <= maxBytes else { throw SelectorConfigError.tooLarge }
        if containsRejectedPayload(data) {
            throw SelectorConfigError.unsafeContent
        }
        let config: SelectorConfig
        do {
            config = try JSONDecoder().decode(SelectorConfig.self, from: data)
        } catch {
            throw SelectorConfigError.invalidJSON
        }
        try validate(config)
        return config
    }

    public static func validate(_ config: SelectorConfig) throws {
        guard config.version == 1 else { throw SelectorConfigError.unsupportedVersion }
        guard !config.posts.containers.isEmpty, !config.posts.permalink.isEmpty else {
            throw SelectorConfigError.incomplete
        }
        guard !config.posts.sponsored.isEmpty || !config.text.sponsored.isEmpty else {
            throw SelectorConfigError.incomplete
        }

        let hideLists = [
            config.hide.reels,
            config.hide.explore,
            config.hide.suggested,
            config.hide.install
        ]
        let postLists = [
            config.posts.containers,
            config.posts.permalink,
            config.posts.sponsored
        ]
        for list in hideLists + postLists {
            guard list.count <= maxItemsPerList else { throw SelectorConfigError.tooLarge }
            for selector in list {
                try validateSelector(selector)
            }
        }
        for selector in config.hide.reels + config.hide.explore + config.hide.suggested + config.hide.install {
            try rejectBlanketSelector(selector)
        }
        for text in config.text.suggested + config.text.sponsored + config.text.install {
            try validateText(text)
        }
    }

    private static func validateSelector(_ selector: String) throws {
        guard !selector.isEmpty, selector.count <= maxSelectorLength else {
            throw SelectorConfigError.unsafeContent
        }
        let lowered = selector.lowercased()
        let banned = [
            "javascript:", "vbscript:", "expression(", "url(", "@import",
            "<", "{", "}", ";", "`", "/*", "*/", "\\", "\n", "\r"
        ]
        if banned.contains(where: { lowered.contains($0) }) {
            throw SelectorConfigError.unsafeContent
        }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_=:.[]#*,>+~|^$'\"()/"
        )
        if selector.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw SelectorConfigError.unsafeContent
        }
    }

    private static func rejectBlanketSelector(_ selector: String) throws {
        let bare = selector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let banned: Set<String> = ["*", "html", "body", "head", ":root", "script", "style"]
        if banned.contains(bare) {
            throw SelectorConfigError.unsafeContent
        }
    }

    private static func validateText(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxTextLength else {
            throw SelectorConfigError.unsafeContent
        }
        let lowered = trimmed.lowercased()
        if lowered.contains("<") || lowered.contains(">") || lowered.contains("{") || lowered.contains("}") || lowered.contains("javascript:") {
            throw SelectorConfigError.unsafeContent
        }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 &'.,:-"
        )
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw SelectorConfigError.unsafeContent
        }
    }

    private static func containsRejectedPayload(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else {
            return true
        }
        let banned = ["<script", "</script", "javascript:", "eval(", "function(", "=>"]
        return banned.contains(where: { text.contains($0) })
    }
}

public enum RemoteConfigPolicy {
    public static func accepts(statusCode: Int, mimeType: String?, byteCount: Int) -> Bool {
        guard (200..<300).contains(statusCode) else { return false }
        guard byteCount > 0, byteCount <= SelectorConfigValidator.maxBytes else { return false }
        let mime = (mimeType ?? "").lowercased()
        if mime.contains("javascript") || mime.contains("ecmascript") || mime.contains("html") {
            return false
        }
        return true
    }
}

public protocol ConfigFetching {
    func fetch(from url: URL) async throws -> Data
}

public enum RemoteConfigOutcome: Equatable {
    /// No remote URL was configured.
    case bundled
    /// A remote document passed validation. It is still only selector data.
    case remote(SelectorConfig)
    /// The response was missing, too big, not JSON, or not a selector document.
    /// Callers must keep using the bundled config.
    case rejected
}

public struct RemoteConfigClient {
    public var fetcher: ConfigFetching
    public var bundled: SelectorConfig

    public init(fetcher: ConfigFetching, bundled: SelectorConfig) {
        self.fetcher = fetcher
        self.bundled = bundled
    }

    /// Fetches selector data. The fetcher is never asked to evaluate a script.
    /// A non-https URL is ignored and does not call the fetcher.
    public func load(remoteURL: URL?) async -> RemoteConfigOutcome {
        guard let remoteURL, RemoteConfigURL.isAllowed(remoteURL) else {
            return .bundled
        }
        do {
            let data = try await fetcher.fetch(from: remoteURL)
            let config = try SelectorConfigValidator.validate(data)
            return .remote(config)
        } catch {
            return .rejected
        }
    }
}
