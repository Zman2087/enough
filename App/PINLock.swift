import CryptoKit
import FilterEngine
import Foundation
import Security

/// Settings lock: a friend picks a PIN so loosening your limits takes their help.
/// Only a salted SHA-256 digest is stored, next to the settings. Wrong attempts pause
/// the prompt for a minute after a few tries.
@MainActor
final class PINLock: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var pausedUntil: Date?

    private let store: PINLockStore
    private var wrongAttempts = 0

    init(store: PINLockStore) {
        self.store = store
        self.isEnabled = store.load() != nil
    }

    enum Outcome: Equatable {
        case accepted
        case wrong(remaining: Int)
        case paused(until: Date)
    }

    func set(pin: String) -> Bool {
        guard SettingsLock.isValidPIN(pin) else { return false }
        let salt = Self.randomSalt()
        store.save(PINRecord(salt: salt, digest: Self.digest(pin: pin, salt: salt)))
        isEnabled = true
        wrongAttempts = 0
        return true
    }

    func check(_ pin: String, now: Date = Date()) -> Outcome {
        if let pausedUntil, now < pausedUntil { return .paused(until: pausedUntil) }
        pausedUntil = nil
        guard let record = store.load() else { return .accepted }
        if Self.digest(pin: pin, salt: record.salt) == record.digest {
            wrongAttempts = 0
            return .accepted
        }
        wrongAttempts += 1
        if wrongAttempts >= SettingsLock.attemptsBeforePause {
            wrongAttempts = 0
            let until = now.addingTimeInterval(SettingsLock.pauseSeconds)
            pausedUntil = until
            return .paused(until: until)
        }
        return .wrong(remaining: SettingsLock.attemptsBeforePause - wrongAttempts)
    }

    /// Removes the lock. Call only after `check` accepted the PIN.
    func remove() {
        store.clear()
        isEnabled = false
        wrongAttempts = 0
    }

    private static func digest(pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        }
        return Data(bytes)
    }
}
