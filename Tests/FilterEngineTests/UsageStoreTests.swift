import XCTest
@testable import FilterEngine

final class UsageStoreTests: XCTestCase {
    private let calendar = FixturePaths.newYorkCalendar()

    func testPermalinkCountsOncePerDay() {
        let harness = Harness(calendar: calendar)
        let morning = FixturePaths.date(2026, 11, 3, 9, 0, calendar: calendar)
        let first = harness.usage.record(permalink: "https://www.instagram.com/p/AbC123/?igsh=1", now: morning)
        let second = harness.usage.record(permalink: "p/AbC123", now: morning)
        let reel = harness.usage.record(permalink: "/reel/AbC123/", now: morning)

        XCTAssertTrue(first.acceptedNew)
        XCTAssertEqual(first.count, 1)
        XCTAssertFalse(first.atCap)
        XCTAssertFalse(second.acceptedNew)
        XCTAssertEqual(second.count, 1)
        XCTAssertTrue(reel.acceptedNew)
        XCTAssertEqual(reel.count, 2)
        XCTAssertEqual(first.dayKey, "2026-11-03")
    }

    func testInvalidPermalinkIsIgnored() {
        let harness = Harness(calendar: calendar)
        let now = FixturePaths.date(2026, 11, 3, 9, 0, calendar: calendar)
        let snapshot = harness.usage.record(permalink: "javascript:alert(1)", now: now)
        XCTAssertFalse(snapshot.acceptedNew)
        XCTAssertEqual(snapshot.count, 0)
        XCTAssertNil(Permalink.normalize("not a post"))
        XCTAssertNil(Permalink.normalize(""))
    }

    func testDailyResetClearsTheSeenSet() {
        let harness = Harness(calendar: calendar)
        let before = FixturePaths.date(2026, 11, 3, 3, 59, calendar: calendar)
        let after = FixturePaths.date(2026, 11, 3, 4, 0, calendar: calendar)
        let recorded = harness.usage.record(permalink: "/p/POST1/", now: before)
        XCTAssertEqual(recorded.dayKey, "2026-11-02")
        XCTAssertEqual(recorded.count, 1)

        let rolled = harness.usage.snapshot(now: after)
        XCTAssertEqual(rolled.dayKey, "2026-11-03")
        XCTAssertEqual(rolled.count, 0)
        XCTAssertFalse(rolled.atCap)

        let stored = try! JSONDecoder().decode(DailyUsage.self, from: harness.memory.data(forKey: EnoughConstants.usageKey)!)
        XCTAssertEqual(stored.seen, [])
        XCTAssertFalse(String(data: harness.memory.data(forKey: EnoughConstants.usageKey)!, encoding: .utf8)!.contains("POST1"))

        let again = harness.usage.record(permalink: "/p/POST1/", now: after)
        XCTAssertTrue(again.acceptedNew)
        XCTAssertEqual(again.count, 1)
        XCTAssertEqual(again.dayKey, "2026-11-03")
    }

    func testCapBoundary() {
        let harness = Harness(calendar: calendar, cap: 2)
        let now = FixturePaths.date(2026, 11, 3, 12, 0, calendar: calendar)
        let first = harness.usage.record(permalink: "/p/ONE/", now: now)
        let second = harness.usage.record(permalink: "/p/TWO/", now: now)
        XCTAssertFalse(first.atCap)
        XCTAssertTrue(second.atCap)
        XCTAssertEqual(second.count, 2)
        XCTAssertTrue(CapPolicy.shouldBlock(surface: .feed, snapshot: second))
        XCTAssertFalse(CapPolicy.shouldBlock(surface: .direct, snapshot: second))
    }

    func testCountStopsAtTheCap() {
        let harness = Harness(calendar: calendar, cap: 1)
        let now = FixturePaths.date(2026, 11, 3, 12, 0, calendar: calendar)
        _ = harness.usage.record(permalink: "/p/ONE/", now: now)
        let extra = harness.usage.record(permalink: "/p/TWO/", now: now)
        XCTAssertFalse(extra.acceptedNew)
        XCTAssertEqual(extra.count, 1)
        XCTAssertTrue(extra.atCap)
    }

    func testSeenListStopsAtTheStorageCap() {
        let harness = Harness(calendar: calendar, cap: 30, maxSeen: 2)
        let now = FixturePaths.date(2026, 11, 3, 12, 0, calendar: calendar)
        XCTAssertTrue(harness.usage.record(permalink: "/p/ONE/", now: now).acceptedNew)
        XCTAssertTrue(harness.usage.record(permalink: "/p/TWO/", now: now).acceptedNew)
        let third = harness.usage.record(permalink: "/p/THREE/", now: now)
        XCTAssertFalse(third.acceptedNew)
        XCTAssertEqual(third.count, 2)
    }

    func testChangingTheCapRecomputesAtCap() {
        let harness = Harness(calendar: calendar, cap: 30)
        let now = FixturePaths.date(2026, 11, 3, 12, 0, calendar: calendar)
        let seen = harness.usage.record(permalink: "/p/ONE/", now: now)
        XCTAssertFalse(seen.atCap)
        harness.settings.dailyCap = 1
        let snapshot = harness.usage.snapshot(now: now)
        XCTAssertTrue(snapshot.atCap)
        XCTAssertEqual(snapshot.cap, 1)
    }

    func testDisablingTheCapStopsBlocking() {
        let harness = Harness(calendar: calendar, cap: 1)
        let now = FixturePaths.date(2026, 11, 3, 12, 0, calendar: calendar)
        _ = harness.usage.record(permalink: "/p/ONE/", now: now)
        harness.settings.capEnabled = false
        let snapshot = harness.usage.snapshot(now: now)
        XCTAssertFalse(snapshot.atCap)
        XCTAssertFalse(CapPolicy.shouldBlock(surface: .feed, snapshot: snapshot))
    }

    func testSeenLibrarySurvivesTheDailyReset() {
        let harness = Harness(calendar: calendar)
        let library = SeenLibrary(store: harness.memory, maxCount: 3)
        let before = FixturePaths.date(2026, 11, 3, 3, 59, calendar: calendar)
        let after = FixturePaths.date(2026, 11, 3, 4, 0, calendar: calendar)
        XCTAssertTrue(library.record("/p/OLD1/"))
        XCTAssertFalse(library.record("p/OLD1"))
        _ = harness.usage.record(permalink: "/p/OLD1/", now: before)
        let rolled = harness.usage.snapshot(now: after)
        XCTAssertEqual(rolled.count, 0)
        XCTAssertTrue(library.contains("https://www.instagram.com/p/OLD1/?x=1"))
        XCTAssertEqual(library.permalinks(), ["p/OLD1"])
        XCTAssertTrue(library.record("/p/TWO/"))
        XCTAssertTrue(library.record("/p/THREE/"))
        XCTAssertTrue(library.record("/p/FOUR/"))
        XCTAssertEqual(library.permalinks(), ["p/TWO", "p/THREE", "p/FOUR"])
        XCTAssertFalse(library.record("not a post"))
    }

    func testSettingsRoundTripThroughUserDefaults() {
        let suite = "test.enough.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsKeyValueStore(defaults: defaults)
        let settingsStore = SettingsStore(store: store)
        var settings = EnoughSettings.default
        settings.dailyCap = 12
        settings.resetHour = 21
        settings.resetMinute = 15
        settings.hideReels = false
        settings.remoteConfigURL = "https://example.com/selectors.json"
        settingsStore.save(settings)
        let loaded = settingsStore.load()
        XCTAssertEqual(loaded.dailyCap, 12)
        XCTAssertEqual(loaded.resetHour, 21)
        XCTAssertEqual(loaded.resetMinute, 15)
        XCTAssertFalse(loaded.hideReels)
        XCTAssertEqual(loaded.remoteConfigURL, "https://example.com/selectors.json")
    }
}

private final class SettingsBox {
    var settings: EnoughSettings
    init(_ settings: EnoughSettings) {
        self.settings = settings
    }
}

private final class Harness {
    let memory: MemoryKeyValueStore
    let box: SettingsBox
    let usage: UsageStore

    var settings: EnoughSettings {
        get { box.settings }
        set { box.settings = newValue }
    }

    init(calendar: Calendar, cap: Int = 30, maxSeen: Int = 50) {
        var initial = EnoughSettings.default
        initial.dailyCap = cap
        let box = SettingsBox(initial)
        let memory = MemoryKeyValueStore()
        self.box = box
        self.memory = memory
        self.usage = UsageStore(
            store: memory,
            settings: { box.settings },
            calendar: calendar,
            maxSeen: maxSeen
        )
    }
}
