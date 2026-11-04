import XCTest
@testable import FilterEngine

final class SelectorConfigTests: XCTestCase {
    func testBundledFileMatchesTheFallback() throws {
        let data = try Data(contentsOf: FixturePaths.selectors)
        let config = try SelectorConfigValidator.validate(data)
        XCTAssertEqual(config, .fallback)
        XCTAssertFalse(config.hide.explore.contains { $0.contains("search") })
        XCTAssertFalse(config.posts.sponsored.isEmpty)
        XCTAssertFalse(config.text.sponsored.isEmpty)
        let css = try String(contentsOf: FixturePaths.hideCSS, encoding: .utf8)
        XCTAssertTrue(css.contains(".enough-hidden"))
        XCTAssertTrue(css.contains(":not(.enough-keep)"))
        XCTAssertTrue(css.contains("apps.apple.com"))
        XCTAssertTrue(css.contains(".enough-keep a[href*=\"apps.apple.com\"]"))
        XCTAssertFalse(config.hide.install.isEmpty)
        XCTAssertTrue(config.text.install.contains("Open app"))
        XCTAssertTrue(config.text.install.contains("Get the app"))
    }

    func testOlderSelectorDocumentsStillValidateWithoutInstallRules() throws {
        let object = try JSONSerialization.jsonObject(with: Data(SelectorConfig.bundledJSON.utf8)) as! [String: Any]
        var root = object
        var hide = root["hide"] as! [String: Any]
        hide.removeValue(forKey: "install")
        root["hide"] = hide
        var text = root["text"] as! [String: Any]
        text.removeValue(forKey: "install")
        root["text"] = text
        let data = try JSONSerialization.data(withJSONObject: root)
        let config = try SelectorConfigValidator.validate(data)
        XCTAssertEqual(config.hide.install, [])
        XCTAssertEqual(config.text.install, [])
    }

    func testSettingsAreClamped() {
        var settings = EnoughSettings.default
        settings.dailyCap = 0
        settings.resetHour = 40
        settings.resetMinute = -4
        settings.remoteConfigURL = "http://example.com/selectors.json"
        let clean = settings.sanitized()
        XCTAssertEqual(clean.dailyCap, 1)
        XCTAssertEqual(clean.resetHour, 23)
        XCTAssertEqual(clean.resetMinute, 0)
        XCTAssertNil(clean.remoteConfigURL)

        settings.dailyCap = 9000
        settings.remoteConfigURL = " https://cdn.example.com/selectors.json "
        let high = settings.sanitized()
        XCTAssertEqual(high.dailyCap, 500)
        XCTAssertEqual(high.remoteConfigURL, "https://cdn.example.com/selectors.json")
        XCTAssertNil(RemoteConfigURL.normalize("javascript:alert(1)"))
    }

    func testValidatorRejectsCodeAndBlanketSelectors() {
        XCTAssertThrowsError(try SelectorConfigValidator.validate(Data("function(){return 1}".utf8))) { error in
            XCTAssertEqual(error as? SelectorConfigError, .unsafeContent)
        }
        XCTAssertThrowsError(try SelectorConfigValidator.validate(Data("<html><script>alert(1)</script></html>".utf8)))
        XCTAssertThrowsError(try validate(hideReels: ["a{color:red}"]))
        XCTAssertThrowsError(try validate(hideReels: ["a[href='javascript:alert(1)']"]))
        XCTAssertThrowsError(try validate(hideReels: ["*"]))
        XCTAssertThrowsError(try validate(hideReels: ["body"]))
        XCTAssertThrowsError(try SelectorConfigValidator.validate(config(version: 2)))
        XCTAssertThrowsError(try SelectorConfigValidator.validate(config(sponsored: [], sponsoredText: [])))
    }

    func testBootScriptRoundTripsAsData() throws {
        let settings = EnoughSettings.default
        let script = WebBoot.installationScript(config: .fallback, settings: settings, css: HideCSS.fallback)
        XCTAssertTrue(script.hasPrefix("window.__ENOUGH_BOOT__ = {"))
        XCTAssertTrue(script.hasSuffix(";"))
        XCTAssertFalse(script.contains("<script"))
        let json = String(script.dropFirst("window.__ENOUGH_BOOT__ = ".count).dropLast())
        let payload = try JSONDecoder().decode(BootPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.config, .fallback)
        XCTAssertTrue(payload.toggles.hideReels)
        XCTAssertEqual(payload.seen, [])
        XCTAssertEqual(payload.homeURL, "https://www.instagram.com/")
        XCTAssertEqual(payload.hideSponsored, PlatformCatalog.instagram.hidesAds)
        #if !PERSONAL_BUILD
        XCTAssertFalse(payload.hideSponsored)
        #endif
        XCTAssertTrue(payload.toggles.hideExplore)
        XCTAssertTrue(payload.toggles.hideSuggested)
        XCTAssertTrue(payload.css.contains(".enough-keep"))
        XCTAssertTrue(WebBoot.reconfigureScript(config: .fallback, settings: settings, css: "x").contains("window.Enough.reconfigure("))
    }

    func testRemoteClientUsesOnlyValidatedData() async {
        let bundled = SelectorConfig.fallback
        let httpFetcher = RecordingFetcher(result: .success(Data("{}".utf8)))
        let httpClient = RemoteConfigClient(fetcher: httpFetcher, bundled: bundled)
        let ignored = await httpClient.load(remoteURL: URL(string: "http://example.com/selectors.json"))
        XCTAssertEqual(ignored, .bundled)
        XCTAssertTrue(httpFetcher.urls.isEmpty)

        let thrown = RecordingFetcher(result: .failure(URLError(.notConnectedToInternet)))
        let thrownClient = RemoteConfigClient(fetcher: thrown, bundled: bundled)
        let failed = await thrownClient.load(remoteURL: URL(string: "https://example.com/selectors.json"))
        XCTAssertEqual(failed, .rejected)

        let script = RecordingFetcher(result: .success(Data("var x = 1;".utf8)))
        let scriptClient = RemoteConfigClient(fetcher: script, bundled: bundled)
        let rejected = await scriptClient.load(remoteURL: URL(string: "https://example.com/filter.js"))
        XCTAssertEqual(rejected, .rejected)

        var remote = bundled
        remote.hide.reels = ["a[href='/reels/']"]
        let data = try! JSONEncoder().encode(remote)
        let okFetcher = RecordingFetcher(result: .success(data))
        let okClient = RemoteConfigClient(fetcher: okFetcher, bundled: bundled)
        let loaded = await okClient.load(remoteURL: URL(string: "https://example.com/selectors.json"))
        XCTAssertEqual(loaded, .remote(remote))

        let none = await okClient.load(remoteURL: nil)
        XCTAssertEqual(none, .bundled)
    }

    func testRemotePolicyRejectsScriptPayloadsBeforeUse() {
        XCTAssertTrue(RemoteConfigPolicy.accepts(statusCode: 200, mimeType: "application/json", byteCount: 32))
        XCTAssertTrue(RemoteConfigPolicy.accepts(statusCode: 200, mimeType: nil, byteCount: 32))
        XCTAssertFalse(RemoteConfigPolicy.accepts(statusCode: 200, mimeType: "application/javascript", byteCount: 32))
        XCTAssertFalse(RemoteConfigPolicy.accepts(statusCode: 200, mimeType: "text/html", byteCount: 32))
        XCTAssertFalse(RemoteConfigPolicy.accepts(statusCode: 404, mimeType: "application/json", byteCount: 32))
        XCTAssertFalse(RemoteConfigPolicy.accepts(statusCode: 200, mimeType: "application/json", byteCount: SelectorConfigValidator.maxBytes + 1))
    }

    #if SWIFT_PACKAGE
    func testSwiftPackageCopiesTheSelectorResource() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "selectors", withExtension: "json"))
        let config = try SelectorConfigValidator.validate(Data(contentsOf: url))
        XCTAssertEqual(config, .fallback)
    }
    #endif

    private func validate(hideReels: [String]) throws {
        try SelectorConfigValidator.validate(config(hideReels: hideReels))
    }

    private func config(
        version: Int = 1,
        hideReels: [String] = ["a[href='/reels/']"],
        sponsored: [String] = ["[data-sponsored='1']"],
        sponsoredText: [String] = ["Sponsored"]
    ) -> SelectorConfig {
        SelectorConfig(
            version: version,
            hide: .init(reels: hideReels, explore: ["a[href='/explore/']"], suggested: []),
            posts: .init(containers: ["article"], permalink: ["a[href*='/p/']"], sponsored: sponsored),
            text: .init(suggested: ["Suggested for you"], sponsored: sponsoredText)
        )
    }
}

private final class RecordingFetcher: ConfigFetching {
    var urls: [URL] = []
    var result: Result<Data, Error>

    init(result: Result<Data, Error>) {
        self.result = result
    }

    func fetch(from url: URL) async throws -> Data {
        urls.append(url)
        return try result.get()
    }
}
