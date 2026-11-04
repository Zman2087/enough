import Foundation

public enum Surface: String, Equatable, Codable {
    case feed
    case reels
    case explore
    case direct
    case search
    case profile
    case post
    case login
    case stories
    case other
}

public enum NavigationDecision: Equatable {
    case allow
    case cancel
}

/// One site's rules. The app ships Instagram. TikTok and YouTube are profiles only,
/// so a later port can plug them in without another ad-hiding path.
public struct PlatformProfile: Equatable {
    public let id: String
    public let displayName: String
    public let hostSuffixes: [String]
    public let homeURL: URL
    public let loginURL: URL
    public let searchPath: String
    public let handoffSchemes: [String]
    public let sessionCookieName: String
    public let installPhrases: [String]
    /// Intent only. `hidesAds` is true solely when this is set and the
    /// Personal build configuration compiled `PERSONAL_BUILD`. Release cannot.
    let requestsSponsoredHiding: Bool

    public init(
        id: String,
        displayName: String,
        hostSuffixes: [String],
        homeURL: URL,
        loginURL: URL,
        searchPath: String,
        handoffSchemes: [String],
        sessionCookieName: String,
        installPhrases: [String],
        requestsSponsoredHiding: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.hostSuffixes = hostSuffixes
        self.homeURL = homeURL
        self.loginURL = loginURL
        self.searchPath = searchPath
        self.handoffSchemes = handoffSchemes
        self.sessionCookieName = sessionCookieName
        self.installPhrases = installPhrases
        self.requestsSponsoredHiding = requestsSponsoredHiding
    }

    /// In-feed sponsored posts are hidden only in the Enough Personal scheme.
    /// Release and Debug compile this to false. No network blocking either way.
    public var hidesAds: Bool {
        #if PERSONAL_BUILD
        return requestsSponsoredHiding
        #else
        return false
        #endif
    }

    public func matches(host: String) -> Bool {
        var host = host.lowercased()
        while host.hasPrefix(".") {
            host.removeFirst()
        }
        if host.hasSuffix(".") { return false }
        return hostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
    }

    public func isAppHandoff(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if handoffSchemes.contains(scheme) || scheme == "itms" || scheme == "itms-apps" || scheme == "itmss" {
            return true
        }
        guard let host = url.host?.lowercased() else { return false }
        if host == "apps.apple.com" || host == "itunes.apple.com" || host.hasSuffix(".itunes.apple.com") {
            return true
        }
        return host == "appsto.re" || host.hasSuffix(".appsto.re")
    }
}

public enum PlatformCatalog {
    public static let instagram = PlatformProfile(
        id: "instagram",
        displayName: "Instagram",
        hostSuffixes: ["instagram.com"],
        homeURL: URL(string: "https://www.instagram.com/")!,
        loginURL: URL(string: "https://www.instagram.com/accounts/login/")!,
        searchPath: "/explore/search/",
        handoffSchemes: ["instagram"],
        sessionCookieName: "sessionid",
        installPhrases: ["Open app", "Open Instagram", "Get the app", "Get Instagram", "Use the app", "Open in app", "Open in the app", "View in app"],
        requestsSponsoredHiding: true
    )

    /// Not loaded by the app yet. Subscriptions-only, install prompts removed, no ad hiding.
    public static let tiktok = PlatformProfile(
        id: "tiktok",
        displayName: "TikTok",
        hostSuffixes: ["tiktok.com"],
        homeURL: URL(string: "https://www.tiktok.com/following")!,
        loginURL: URL(string: "https://www.tiktok.com/login")!,
        searchPath: "/search",
        handoffSchemes: ["tiktok"],
        sessionCookieName: "sessionid",
        installPhrases: ["Open app", "Get the app", "Open in app"]
    )

    /// Not loaded by the app yet. Subscriptions feed, install prompts removed, no ad hiding.
    public static let youtube = PlatformProfile(
        id: "youtube",
        displayName: "YouTube",
        hostSuffixes: ["youtube.com"],
        homeURL: URL(string: "https://www.youtube.com/feed/subscriptions")!,
        loginURL: URL(string: "https://www.youtube.com/account")!,
        searchPath: "/results",
        handoffSchemes: ["youtube", "vnd.youtube"],
        sessionCookieName: "SAPISID",
        installPhrases: ["Open app", "Open in app"]
    )

    public static let all = [instagram, tiktok, youtube]
    public static let active = instagram

    public static func profile(id: String) -> PlatformProfile? {
        all.first { $0.id == id }
    }
}

/// Main-frame allowlist for the active platform. Subframes are a separate decision
/// in the web view: ad frames stay loadable, app-install handoffs do not.
public enum NavigationPolicy {
    public static func isInstagramHost(_ host: String) -> Bool {
        PlatformCatalog.instagram.matches(host: host)
    }

    public static func isAppHandoff(_ url: URL) -> Bool {
        isAppHandoff(url, platform: PlatformCatalog.active)
    }

    public static func isAppHandoff(_ url: URL, platform: PlatformProfile) -> Bool {
        platform.isAppHandoff(url)
    }

    public static func decide(url: URL) -> NavigationDecision {
        decide(url: url, platform: PlatformCatalog.active)
    }

    public static func decide(url: URL, platform: PlatformProfile) -> NavigationDecision {
        if platform.isAppHandoff(url) {
            return .cancel
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" {
            return .allow
        }
        guard scheme == "https" else { return .cancel }
        guard let host = url.host, platform.matches(host: host) else { return .cancel }
        return .allow
    }
}

public enum RoutePath {
    /// A path reported by the page. Rejects full URLs and anything that is not a path.
    public static func sanitize(_ raw: String) -> String? {
        guard raw.rangeOfCharacter(from: .newlines) == nil else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard !trimmed.contains("://"), !trimmed.contains("\\") else { return nil }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("?") else { return nil }
        if trimmed.hasPrefix("?") {
            return "/" + trimmed
        }
        return trimmed
    }
}

public enum CapPolicy {
    /// Surfaces the overlay covers. Messages, search, profiles, a single opened
    /// post, and the login page stay usable so the cap blocks the feed only.
    public static let blockedSurfaces: Set<Surface> = [.feed, .reels, .explore, .stories]

    public static func surface(for url: URL) -> Surface {
        guard let host = url.host, NavigationPolicy.isInstagramHost(host) else {
            return .other
        }
        return surface(path: url.path)
    }

    public static func surface(path: String) -> Surface {
        let withoutQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        let bare = withoutQuery.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutQuery
        let parts = bare.split(separator: "/").map { String($0) }
        if parts.isEmpty {
            return .feed
        }
        let first = parts[0].lowercased()
        if first == "reels" || first == "reel" {
            return .reels
        }
        if first == "stories" {
            return .stories
        }
        if first == "direct" {
            return .direct
        }
        if first == "explore" {
            if parts.count >= 2, parts[1].lowercased() == "search" {
                return .search
            }
            return .explore
        }
        if first == "accounts" || first == "login" {
            return .login
        }
        if first == "p" {
            return .post
        }
        if parts.count >= 2, parts[1].lowercased() == "reels", !reservedProfileSegments.contains(first) {
            return .reels
        }
        if parts.count == 1, !reservedProfileSegments.contains(first) {
            return .profile
        }
        if parts.count == 2,
           profileSubpages.contains(parts[1].lowercased()),
           !reservedProfileSegments.contains(first) {
            return .profile
        }
        return .other
    }

    public static func shouldBlock(surface: Surface, snapshot: UsageSnapshot) -> Bool {
        guard snapshot.capEnabled, snapshot.count >= snapshot.cap else { return false }
        return blockedSurfaces.contains(surface)
    }

    /// First path segments that are site sections, not usernames.
    static let reservedProfileSegments: Set<String> = [
        "about", "accounts", "ar", "challenge", "clips", "developer", "direct",
        "directory", "emails", "explore", "fxcal", "legal", "live", "login",
        "nametag", "oauth", "p", "privacy", "reel", "reels", "share", "stories",
        "terms", "tv"
    ]

    static let profileSubpages: Set<String> = [
        "channel", "followers", "following", "saved", "tagged"
    ]
}

/// A cookie reduced to what the start-page choice needs. The value itself is not kept.
public struct CookieHint: Equatable {
    public var name: String
    public var domain: String
    public var hasValue: Bool

    public init(name: String, domain: String, hasValue: Bool) {
        self.name = name
        self.domain = domain
        self.hasValue = hasValue
    }
}

public enum FeedPresentation {
    /// The caught-up screen covers the feed only. Search, messages, and a profile stay available.
    /// The daily cap wins when both are true.
    public static func showsCaughtUp(caughtUp: Bool, atCap: Bool, loading: Bool, surface: Surface) -> Bool {
        caughtUp && !atCap && !loading && surface == .feed
    }
}

/// With no session cookie, open the login form. Otherwise open that platform's following feed.
public enum StartDestination {
    public static var homeURL: URL { PlatformCatalog.active.homeURL }
    public static var loginURL: URL { PlatformCatalog.active.loginURL }

    public static func hasSession(_ cookies: [CookieHint]) -> Bool {
        hasSession(cookies, platform: PlatformCatalog.active)
    }

    public static func hasSession(_ cookies: [CookieHint], platform: PlatformProfile) -> Bool {
        cookies.contains { cookie in
            cookie.name.compare(platform.sessionCookieName, options: .caseInsensitive) == .orderedSame
                && cookie.hasValue
                && platform.matches(host: normalizedDomain(cookie.domain))
        }
    }

    public static func url(hasSession: Bool) -> URL {
        url(hasSession: hasSession, platform: PlatformCatalog.active)
    }

    public static func url(hasSession: Bool, platform: PlatformProfile) -> URL {
        hasSession ? platform.homeURL : platform.loginURL
    }

    static func normalizedDomain(_ domain: String) -> String {
        var domain = domain.lowercased()
        while domain.hasPrefix(".") {
            domain.removeFirst()
        }
        return domain
    }
}
