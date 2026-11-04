import Foundation

/// Identifiers shared by the app and the extension stubs.
/// The App Group holds settings and today's count. It never holds a password,
/// a cookie, a caption, or a profile.
public enum EnoughConstants {
    public static let appGroupID = "group.app.enough.shared"
    public static let settingsKey = "enough.settings"
    public static let usageKey = "enough.usage"
    public static let messageHandlerName = "enough"
    public static let defaultDailyCap = 30
    public static let minimumCap = 1
    public static let maximumCap = 500
    public static let maxSeenPermalinks = 2000
    /// Shortcodes already shown, kept across daily resets. Not uploaded.
    public static let seenLibraryKey = "enough.seen.posts"
    public static let lockKey = "enough.lock"
    public static let seenLibraryMax = 4000
    /// Instagram's own Following feed. Suggested posts stay hidden on top of this.
    public static let startURLString = "https://www.instagram.com/"

    public static var startURL: URL { PlatformCatalog.active.homeURL }
}
