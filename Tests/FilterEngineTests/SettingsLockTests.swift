import XCTest
@testable import FilterEngine

final class SettingsLockTests: XCTestCase {
    private let base = EnoughSettings.default

    func testTighteningNeverNeedsThePIN() {
        var lower = base
        lower.dailyCap = max(EnoughConstants.minimumCap, base.dailyCap - 10)
        XCTAssertFalse(SettingsLock.loosens(from: base, to: lower))

        var off = base
        off.hideReels = false
        var backOn = off
        backOn.hideReels = true
        XCTAssertFalse(SettingsLock.loosens(from: off, to: backOn))
        XCTAssertFalse(SettingsLock.loosens(from: base, to: base))
    }

    func testLooseningNeedsThePIN() {
        var higher = base
        higher.dailyCap = base.dailyCap + 1
        XCTAssertTrue(SettingsLock.loosens(from: base, to: higher))

        var uncapped = base
        uncapped.capEnabled = false
        XCTAssertTrue(SettingsLock.loosens(from: base, to: uncapped))

        for path in [\EnoughSettings.hideReels, \.hideExplore, \.hideSuggested] {
            var shown = base
            shown[keyPath: path] = false
            XCTAssertTrue(SettingsLock.loosens(from: base, to: shown))
        }

        var reset = base
        reset.resetHour = (base.resetHour + 1) % 24
        XCTAssertTrue(SettingsLock.loosens(from: base, to: reset))

        var remote = base
        remote.remoteConfigURL = "https://example.com/selectors.json"
        XCTAssertTrue(SettingsLock.loosens(from: base, to: remote))
    }

    func testPINFormat() {
        XCTAssertTrue(SettingsLock.isValidPIN("1234"))
        XCTAssertTrue(SettingsLock.isValidPIN("12345678"))
        XCTAssertFalse(SettingsLock.isValidPIN("123"))
        XCTAssertFalse(SettingsLock.isValidPIN("123456789"))
        XCTAssertFalse(SettingsLock.isValidPIN("12a4"))
        XCTAssertFalse(SettingsLock.isValidPIN("１２３４"))
    }

    func testStoreRoundTripsAndClears() {
        let store = PINLockStore(store: MemoryKeyValueStore())
        XCTAssertNil(store.load())
        let record = PINRecord(salt: Data([1, 2, 3]), digest: Data([4, 5, 6]))
        store.save(record)
        XCTAssertEqual(store.load(), record)
        store.clear()
        XCTAssertNil(store.load())
    }
}
