import XCTest
@testable import FilterEngine

final class PolicyTests: XCTestCase {
    func testRoutesMatchTheSharedFixture() throws {
        let data = try Data(contentsOf: FixturePaths.routes)
        let routes = try JSONDecoder().decode([RouteFixture].self, from: data)
        XCTAssertGreaterThan(routes.count, 10)
        for route in routes {
            let surface = CapPolicy.surface(path: route.path)
            XCTAssertEqual(surface.rawValue, route.surface, route.path)
            let atCap = UsageSnapshot(
                dayKey: "2026-11-03",
                count: 30,
                acceptedNew: false,
                atCap: true,
                cap: 30,
                capEnabled: true
            )
            let below = UsageSnapshot(
                dayKey: "2026-11-03",
                count: 29,
                acceptedNew: false,
                atCap: false,
                cap: 30,
                capEnabled: true
            )
            XCTAssertEqual(CapPolicy.shouldBlock(surface: surface, snapshot: atCap), route.blockedAtCap, route.path)
            XCTAssertFalse(CapPolicy.shouldBlock(surface: surface, snapshot: below), route.path)
        }
    }

    func testMessagesSearchAndProfilesStayOpenAtTheCap() {
        let snapshot = UsageSnapshot(dayKey: "2026-11-03", count: 30, acceptedNew: false, atCap: true, cap: 30, capEnabled: true)
        XCTAssertTrue(CapPolicy.shouldBlock(surface: .feed, snapshot: snapshot))
        XCTAssertTrue(CapPolicy.shouldBlock(surface: .reels, snapshot: snapshot))
        XCTAssertTrue(CapPolicy.shouldBlock(surface: .explore, snapshot: snapshot))
        XCTAssertFalse(CapPolicy.shouldBlock(surface: .direct, snapshot: snapshot))
        XCTAssertFalse(CapPolicy.shouldBlock(surface: .search, snapshot: snapshot))
        XCTAssertFalse(CapPolicy.shouldBlock(surface: .profile, snapshot: snapshot))
        XCTAssertFalse(CapPolicy.shouldBlock(surface: .post, snapshot: snapshot))
        XCTAssertFalse(CapPolicy.shouldBlock(surface: .login, snapshot: snapshot))
    }

    func testMainFrameStaysOnInstagram() {
        XCTAssertEqual(NavigationPolicy.decide(url: EnoughConstants.startURL), .allow)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://instagram.com/")!), .allow)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://www.instagram.com/direct/inbox/")!), .allow)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://about.instagram.com/")!), .allow)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "http://www.instagram.com/")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://facebook.com/")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://www.instagram.com.evil.com/")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://evilinstagram.com/")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://cdninstagram.com/image.jpg")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "javascript:alert(1)")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "about:blank")!), .allow)
        XCTAssertEqual(NavigationPolicy.decide(url: StartDestination.loginURL), .allow)
    }

    func testAppHandoffStaysInsideTheApp() {
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "instagram://user?username=someone")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "instagram://app")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "itms-apps://itunes.apple.com/app/id389801252")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "itms://itunes.apple.com/app/id389801252")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://apps.apple.com/app/instagram/id389801252")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://itunes.apple.com/app/id389801252")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://geo.itunes.apple.com/app/id389801252")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://appsto.re/us/instagram")!), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(url: StartDestination.homeURL), .allow)
    }

    func testSignedOutStartOpensTheLoginForm() {
        XCTAssertFalse(StartDestination.hasSession([]))
        XCTAssertEqual(StartDestination.url(hasSession: false), StartDestination.loginURL)
        XCTAssertFalse(StartDestination.hasSession([
            CookieHint(name: "sessionid", domain: ".instagram.com", hasValue: false),
            CookieHint(name: "csrftoken", domain: ".instagram.com", hasValue: true),
            CookieHint(name: "sessionid", domain: ".example.com", hasValue: true)
        ]))
    }

    func testSignedInStartOpensTheFeed() {
        let cookies = [
            CookieHint(name: "sessionid", domain: ".instagram.com", hasValue: true)
        ]
        XCTAssertTrue(StartDestination.hasSession(cookies))
        XCTAssertEqual(StartDestination.url(hasSession: true), StartDestination.homeURL)
        XCTAssertEqual(StartDestination.homeURL.absoluteString, "https://www.instagram.com/")
        XCTAssertTrue(StartDestination.hasSession([
            CookieHint(name: "SESSIONID", domain: "www.instagram.com", hasValue: true)
        ]))
    }

    func testOtherPlatformsStayFollowingOnlyAndNeverHideAds() {
        XCTAssertEqual(PlatformCatalog.active.id, "instagram")
        XCTAssertTrue(PlatformCatalog.instagram.requestsSponsoredHiding)
        XCTAssertFalse(PlatformCatalog.tiktok.requestsSponsoredHiding)
        XCTAssertFalse(PlatformCatalog.youtube.requestsSponsoredHiding)
        #if PERSONAL_BUILD
        XCTAssertTrue(PlatformCatalog.instagram.hidesAds)
        #else
        XCTAssertFalse(PlatformCatalog.instagram.hidesAds)
        #endif
        XCTAssertFalse(PlatformCatalog.tiktok.hidesAds)
        XCTAssertFalse(PlatformCatalog.youtube.hidesAds)
        XCTAssertEqual(PlatformCatalog.tiktok.homeURL.absoluteString, "https://www.tiktok.com/following")
        XCTAssertEqual(PlatformCatalog.youtube.homeURL.path, "/feed/subscriptions")
        XCTAssertEqual(
            NavigationPolicy.decide(url: URL(string: "https://www.tiktok.com/following")!, platform: PlatformCatalog.tiktok),
            .allow
        )
        XCTAssertEqual(NavigationPolicy.decide(url: URL(string: "https://www.tiktok.com/following")!), .cancel)
        XCTAssertEqual(
            NavigationPolicy.decide(url: URL(string: "tiktok://feed")!, platform: PlatformCatalog.tiktok),
            .cancel
        )
        XCTAssertEqual(PlatformCatalog.instagram.searchPath, "/explore/search/")
    }

    func testCaughtUpScreenLeavesSearchAvailableAndYieldsToTheCap() {
        XCTAssertTrue(FeedPresentation.showsCaughtUp(caughtUp: true, atCap: false, loading: false, surface: .feed))
        XCTAssertFalse(FeedPresentation.showsCaughtUp(caughtUp: true, atCap: true, loading: false, surface: .feed))
        XCTAssertFalse(FeedPresentation.showsCaughtUp(caughtUp: true, atCap: false, loading: false, surface: .search))
        XCTAssertFalse(FeedPresentation.showsCaughtUp(caughtUp: true, atCap: false, loading: true, surface: .feed))
        XCTAssertFalse(FeedPresentation.showsCaughtUp(caughtUp: false, atCap: false, loading: false, surface: .feed))
    }

    func testRoutePathRejectsFullURLs() {
        XCTAssertEqual(RoutePath.sanitize("/direct/inbox/"), "/direct/inbox/")
        XCTAssertEqual(RoutePath.sanitize("?hl=en"), "/?hl=en")
        XCTAssertNil(RoutePath.sanitize("https://example.com/"))
        XCTAssertNil(RoutePath.sanitize("/ok\n"))
        XCTAssertNil(RoutePath.sanitize("javascript:alert(1)"))
    }
}
