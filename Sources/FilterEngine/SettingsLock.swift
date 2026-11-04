import Foundation

/// An optional PIN that makes it harder to loosen your own limits.
/// The idea is that a friend chooses the PIN and keeps it. Tightening a limit never needs it.
/// Only a salted digest is stored, in the same on-device store as the settings, so deleting
/// the app clears the lock along with everything else.
public enum SettingsLock {
    public static let minimumDigits = 4
    public static let maximumDigits = 8
    /// Wrong attempts allowed before a pause.
    public static let attemptsBeforePause = 5
    public static let pauseSeconds: TimeInterval = 60

    /// True when `new` makes any limit easier to get around than `old`.
    public static func loosens(from old: EnoughSettings, to new: EnoughSettings) -> Bool {
        let before = old.sanitized()
        let after = new.sanitized()
        if before.capEnabled && !after.capEnabled { return true }
        if after.capEnabled && after.dailyCap > before.dailyCap { return true }
        if before.hideReels && !after.hideReels { return true }
        if before.hideExplore && !after.hideExplore { return true }
        if before.hideSuggested && !after.hideSuggested { return true }
        // Moving the reset time can hand out a fresh day early, so any change needs the PIN.
        if before.resetHour != after.resetHour || before.resetMinute != after.resetMinute { return true }
        // A different selector source could stop the filter from matching anything.
        if (before.remoteConfigURL ?? "") != (after.remoteConfigURL ?? "") { return true }
        return false
    }

    /// A PIN is 4 to 8 digits.
    public static func isValidPIN(_ pin: String) -> Bool {
        (minimumDigits...maximumDigits).contains(pin.count) && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// The stored form of the PIN: a random salt and the digest of salt + PIN.
public struct PINRecord: Codable, Equatable {
    public var salt: Data
    public var digest: Data

    public init(salt: Data, digest: Data) {
        self.salt = salt
        self.digest = digest
    }
}

public final class PINLockStore {
    private let store: KeyValueStoring
    private let key: String

    public init(store: KeyValueStoring, key: String = EnoughConstants.lockKey) {
        self.store = store
        self.key = key
    }

    public func load() -> PINRecord? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PINRecord.self, from: data)
    }

    public func save(_ record: PINRecord) {
        store.set(try? JSONEncoder().encode(record), forKey: key)
    }

    public func clear() {
        store.set(nil, forKey: key)
    }
}
