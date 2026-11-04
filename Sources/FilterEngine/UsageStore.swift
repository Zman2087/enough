import Foundation

public struct DailyUsage: Codable, Equatable {
    public var dayKey: String
    public var seen: [String]

    public init(dayKey: String, seen: [String]) {
        self.dayKey = dayKey
        self.seen = seen
    }

    public var count: Int { seen.count }
}

public struct UsageSnapshot: Equatable {
    public var dayKey: String
    public var count: Int
    public var acceptedNew: Bool
    public var atCap: Bool
    public var cap: Int
    public var capEnabled: Bool

    public init(
        dayKey: String,
        count: Int,
        acceptedNew: Bool,
        atCap: Bool,
        cap: Int,
        capEnabled: Bool
    ) {
        self.dayKey = dayKey
        self.count = count
        self.acceptedNew = acceptedNew
        self.atCap = atCap
        self.cap = cap
        self.capEnabled = capEnabled
    }
}

/// On-device count of posts seen today.
/// The seen list is the shortcode of each permalink, kept only so a post counts once.
/// It is deleted at the reset time and is never uploaded.
public final class UsageStore {
    private let store: KeyValueStoring
    private let settings: () -> EnoughSettings
    private let calendar: Calendar
    private let usageKey: String
    private let maxSeen: Int
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        store: KeyValueStoring,
        settings: @escaping () -> EnoughSettings,
        calendar: Calendar,
        usageKey: String = EnoughConstants.usageKey,
        maxSeen: Int = EnoughConstants.maxSeenPermalinks
    ) {
        self.store = store
        self.settings = settings
        self.calendar = calendar
        self.usageKey = usageKey
        self.maxSeen = max(1, maxSeen)
    }

    public func snapshot(now: Date) -> UsageSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let current = settings().sanitized()
        let usage = rollIfNeeded(now: now, settings: current)
        return makeSnapshot(usage: usage, settings: current, acceptedNew: false)
    }

    @discardableResult
    public func record(permalink raw: String, now: Date) -> UsageSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let current = settings().sanitized()
        var usage = rollIfNeeded(now: now, settings: current)
        var accepted = false
        // At the cap nothing more counts, whatever page the post was seen on.
        let atCap = current.capEnabled && usage.seen.count >= current.dailyCap
        if !atCap, let permalink = Permalink.normalize(raw), !usage.seen.contains(permalink) {
            if usage.seen.count < maxSeen {
                usage.seen.append(permalink)
                accepted = true
                persist(usage)
            }
        }
        return makeSnapshot(usage: usage, settings: current, acceptedNew: accepted)
    }

    private func rollIfNeeded(now: Date, settings: EnoughSettings) -> DailyUsage {
        let key = settings.dayBoundary(calendar: calendar).key(for: now).rawValue
        if var existing = load(), existing.dayKey == key {
            if existing.seen.count > maxSeen {
                existing.seen = Array(existing.seen.prefix(maxSeen))
                persist(existing)
            }
            return existing
        }
        let fresh = DailyUsage(dayKey: key, seen: [])
        persist(fresh)
        return fresh
    }

    private func load() -> DailyUsage? {
        guard let data = store.data(forKey: usageKey) else { return nil }
        return try? decoder.decode(DailyUsage.self, from: data)
    }

    private func persist(_ usage: DailyUsage) {
        guard let data = try? encoder.encode(usage) else { return }
        store.set(data, forKey: usageKey)
    }

    private func makeSnapshot(usage: DailyUsage, settings: EnoughSettings, acceptedNew: Bool) -> UsageSnapshot {
        UsageSnapshot(
            dayKey: usage.dayKey,
            count: usage.count,
            acceptedNew: acceptedNew,
            atCap: settings.capEnabled && usage.count >= settings.dailyCap,
            cap: settings.dailyCap,
            capEnabled: settings.capEnabled
        )
    }
}

/// Shortcodes the person has already been shown. This survives the daily reset
/// so yesterday's posts stay collapsed. It never leaves the device.
public final class SeenLibrary {
    private let store: KeyValueStoring
    private let key: String
    private let maxCount: Int
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        store: KeyValueStoring,
        key: String = EnoughConstants.seenLibraryKey,
        maxCount: Int = EnoughConstants.seenLibraryMax
    ) {
        self.store = store
        self.key = key
        self.maxCount = max(1, maxCount)
    }

    public func contains(_ raw: String) -> Bool {
        guard let permalink = Permalink.normalize(raw) else { return false }
        lock.lock()
        defer { lock.unlock() }
        return load().contains(permalink)
    }

    public func permalinks() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    /// Returns true when the shortcode was not stored before.
    @discardableResult
    public func record(_ raw: String) -> Bool {
        guard let permalink = Permalink.normalize(raw) else { return false }
        lock.lock()
        defer { lock.unlock() }
        var items = load()
        if items.contains(permalink) { return false }
        items.append(permalink)
        if items.count > maxCount {
            items.removeFirst(items.count - maxCount)
        }
        persist(items)
        return true
    }

    private func load() -> [String] {
        guard let data = store.data(forKey: key),
              let items = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return items
    }

    private func persist(_ items: [String]) {
        guard let data = try? encoder.encode(items) else { return }
        store.set(data, forKey: key)
    }
}
