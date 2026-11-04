import Foundation

public struct EnoughSettings: Codable, Equatable {
    public var dailyCap: Int
    public var resetHour: Int
    public var resetMinute: Int
    public var hideReels: Bool
    public var hideExplore: Bool
    public var hideSuggested: Bool
    public var capEnabled: Bool
    /// HTTPS URL of a selector JSON document. Nil uses the bundled file.
    /// The value is data, never a script URL.
    public var remoteConfigURL: String?

    public init(
        dailyCap: Int,
        resetHour: Int,
        resetMinute: Int,
        hideReels: Bool,
        hideExplore: Bool,
        hideSuggested: Bool,
        capEnabled: Bool,
        remoteConfigURL: String?
    ) {
        self.dailyCap = dailyCap
        self.resetHour = resetHour
        self.resetMinute = resetMinute
        self.hideReels = hideReels
        self.hideExplore = hideExplore
        self.hideSuggested = hideSuggested
        self.capEnabled = capEnabled
        self.remoteConfigURL = remoteConfigURL
    }

    public static let `default` = EnoughSettings(
        dailyCap: EnoughConstants.defaultDailyCap,
        resetHour: 4,
        resetMinute: 0,
        hideReels: true,
        hideExplore: true,
        hideSuggested: true,
        capEnabled: true,
        remoteConfigURL: nil
    )

    public func sanitized() -> EnoughSettings {
        var copy = self
        copy.dailyCap = min(EnoughConstants.maximumCap, max(EnoughConstants.minimumCap, dailyCap))
        copy.resetHour = min(23, max(0, resetHour))
        copy.resetMinute = min(59, max(0, resetMinute))
        if let raw = remoteConfigURL {
            copy.remoteConfigURL = RemoteConfigURL.normalize(raw)?.absoluteString
        }
        return copy
    }

    public func dayBoundary(calendar: Calendar) -> DayBoundary {
        let clean = sanitized()
        return DayBoundary(hour: clean.resetHour, minute: clean.resetMinute, calendar: calendar)
    }

    public var bootToggles: BootToggles {
        let clean = sanitized()
        return BootToggles(
            hideReels: clean.hideReels,
            hideExplore: clean.hideExplore,
            hideSuggested: clean.hideSuggested
        )
    }
}

public enum RemoteConfigURL {
    /// Accepts only absolute https URLs. Empty input is "no remote config".
    public static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), isAllowed(url) else { return nil }
        return url
    }

    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        guard url.user == nil, url.password == nil else { return false }
        return true
    }
}
