import Foundation

public protocol KeyValueStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class MemoryKeyValueStore: KeyValueStoring {
    private var values: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? {
        values[key]
    }

    public func set(_ data: Data?, forKey key: String) {
        values[key] = data
    }
}

public final class UserDefaultsKeyValueStore: KeyValueStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The App Group suite when the capability is present, otherwise standard
    /// defaults so a simulator run still has a working cap before signing is set up.
    /// Extension processes only see the App Group copy.
    public static func sharedSuite() -> UserDefaults {
        UserDefaults(suiteName: EnoughConstants.appGroupID) ?? .standard
    }
}

public protocol SettingsStoring: AnyObject {
    func load() -> EnoughSettings
    func save(_ settings: EnoughSettings)
}

public final class SettingsStore: SettingsStoring {
    private let store: KeyValueStoring
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(store: KeyValueStoring, key: String = EnoughConstants.settingsKey) {
        self.store = store
        self.key = key
    }

    public func load() -> EnoughSettings {
        guard let data = store.data(forKey: key),
              let decoded = try? decoder.decode(EnoughSettings.self, from: data) else {
            return .default
        }
        return decoded.sanitized()
    }

    public func save(_ settings: EnoughSettings) {
        let clean = settings.sanitized()
        guard let data = try? encoder.encode(clean) else { return }
        store.set(data, forKey: key)
    }
}
