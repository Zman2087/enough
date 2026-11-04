import FilterEngine
import Foundation

struct WebCommand: Equatable {
    enum Kind: Equatable {
        case load(URL)
        case loadInitial
        case reconfigure
        case openProfile
        case navigate(path: String, fallback: URL)
    }

    var id: Int
    var kind: Kind
}

@MainActor
final class FeedModel: ObservableObject {
    @Published var settings: EnoughSettings
    @Published var snapshot: UsageSnapshot
    @Published var surface: Surface
    /// Path of the current page, for app chrome only. Not stored.
    @Published var routePath = "/"
    @Published var isBlocked = false
    @Published var caughtUp = false
    @Published var isLoading = true
    @Published var firstPostPageMilliseconds: Double?
    @Published var loadError: String?
    @Published var configStatus = "Using the bundled selectors."
    @Published var command: WebCommand?

    let settingsStore: SettingsStoring
    let usageStore: UsageStore
    let seenLibrary: SeenLibrary
    private let calendar: Calendar
    private let remoteClient: RemoteConfigClient
    private var config: SelectorConfig
    private var commandSerial = 0
    private var usingRemoteConfig = false

    init(
        settingsStore: SettingsStoring,
        usageStore: UsageStore,
        seenLibrary: SeenLibrary,
        calendar: Calendar,
        config: SelectorConfig,
        remoteClient: RemoteConfigClient
    ) {
        self.settingsStore = settingsStore
        self.usageStore = usageStore
        self.seenLibrary = seenLibrary
        self.calendar = calendar
        self.config = config
        self.remoteClient = remoteClient
        let loaded = settingsStore.load()
        self.settings = loaded
        let initial = usageStore.snapshot(now: Date())
        self.snapshot = initial
        self.surface = .feed
        self.isBlocked = CapPolicy.shouldBlock(surface: .feed, snapshot: initial)
    }

    static func makeShared() -> FeedModel {
        let store = UserDefaultsKeyValueStore(defaults: UserDefaultsKeyValueStore.sharedSuite())
        let settingsStore = SettingsStore(store: store)
        let calendar = Calendar.current
        let usage = UsageStore(
            store: store,
            settings: { settingsStore.load() },
            calendar: calendar
        )
        let seenLibrary = SeenLibrary(store: store)
        let config = EngineResources.bundledConfig()
        let client = RemoteConfigClient(fetcher: URLSessionConfigFetcher(), bundled: config)
        return FeedModel(
            settingsStore: settingsStore,
            usageStore: usage,
            seenLibrary: seenLibrary,
            calendar: calendar,
            config: config,
            remoteClient: client
        )
    }

    var resetClockText: String {
        settings.dayBoundary(calendar: calendar).resetClockText(at: Date())
    }

    func refresh(now: Date = Date()) {
        snapshot = usageStore.snapshot(now: now)
        updateBlock()
    }

    func record(permalink: String, now: Date = Date()) {
        seenLibrary.record(permalink)
        snapshot = usageStore.record(permalink: permalink, now: now)
        updateBlock()
    }

    /// The page has its layout. The launch screen can go now.
    func noteReady() {
        isLoading = false
        loadError = nil
    }

    /// If the page never reports ready (a slow network, a changed site), drop the launch
    /// screen anyway so the web view's own loading state shows.
    func startLaunchFallback(after seconds: Double = 3) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.isLoading, self.loadError == nil else { return }
            self.isLoading = false
        }
    }

    /// Messages has no tab bar on the site, so the app draws one on the inbox list.
    /// Not inside a conversation, where the message box sits at the bottom.
    var showsInboxTabBar: Bool {
        routePath.hasPrefix("/direct/inbox")
    }

    func openHome() {
        navigate("/")
    }

    private func navigate(_ path: String) {
        enqueue(.navigate(path: path, fallback: instagramURL(path)))
    }

    func noteCaughtUp(_ value: Bool) {
        caughtUp = value
    }

    func noteFirstPost(pageMilliseconds: Double) {
        guard firstPostPageMilliseconds == nil else { return }
        firstPostPageMilliseconds = pageMilliseconds
        let sinceLaunch = Date().timeIntervalSince(WebTiming.launched) * 1000
        print(String(format: "Enough time to first post: %.0f ms after navigation start, %.0f ms after launch", pageMilliseconds, sinceLaunch))
        isLoading = false
    }

    var showsCaughtUp: Bool {
        FeedPresentation.showsCaughtUp(
            caughtUp: caughtUp,
            atCap: snapshot.atCap,
            loading: isLoading,
            surface: surface
        )
    }

    func updateRoute(path: String) {
        guard let clean = RoutePath.sanitize(path) else { return }
        routePath = clean
        surface = CapPolicy.surface(path: clean)
        updateBlock()
    }

    func updateRoute(url: URL) {
        guard NavigationPolicy.decide(url: url) == .allow else { return }
        routePath = url.path.isEmpty ? "/" : url.path
        surface = CapPolicy.surface(for: url)
        updateBlock()
    }

    func noteFinishedLoading() {
        isLoading = false
        loadError = nil
    }

    func noteFailedLoading() {
        isLoading = false
        loadError = "Can't reach the site. Check your connection."
    }

    func retry() {
        loadError = nil
        isLoading = true
        enqueue(.loadInitial)
    }

    func openMessages() {
        navigate("/direct/inbox/")
    }

    func openSearch() {
        enqueue(.navigate(path: PlatformCatalog.active.searchPath, fallback: openSearchURL()))
    }

    func openProfile() {
        enqueue(.openProfile)
    }

    func save(settings newSettings: EnoughSettings) {
        let clean = newSettings.sanitized()
        settings = clean
        settingsStore.save(clean)
        refresh()
        enqueue(.reconfigure)
    }

    func refreshRemoteConfig() async {
        let url = settings.remoteConfigURL.flatMap(RemoteConfigURL.normalize)
        // Nothing to fetch and already on the bundled selectors: skip the reconfigure,
        // which would reinstall the scripts and re-run the filter during launch.
        if url == nil && !usingRemoteConfig {
            return
        }
        let outcome = await remoteClient.load(remoteURL: url)
        switch outcome {
        case .bundled:
            usingRemoteConfig = false
            config = remoteClient.bundled
            configStatus = "Using the bundled selectors."
        case .remote(let remote):
            usingRemoteConfig = true
            config = remote
            configStatus = "Using remote selectors."
        case .rejected:
            usingRemoteConfig = false
            config = remoteClient.bundled
            configStatus = "Remote config was rejected. Using the bundled selectors."
        }
        enqueue(.reconfigure)
    }

    func bootScript() -> String {
        WebBoot.installationScript(
            config: config,
            settings: settings,
            css: EngineResources.hideCSS(),
            seen: seenLibrary.permalinks(),
            homeURL: PlatformCatalog.active.homeURL.absoluteString
        )
    }

    /// Whether the daily cap blocks the feed right now, plus the reset time to show.
    var capReached: Bool {
        snapshot.capEnabled && snapshot.count >= snapshot.cap
    }

    /// Cap state for the page, set before `filter.js` runs. Built with the JSON encoder.
    func capScript() -> String {
        let payload = ["reached": capReached ? "1" : "", "resetText": resetClockText]
        let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
        return "window.__ENOUGH_CAP__ = (function (c) { return { reached: !!c.reached, resetText: c.resetText || \"\" }; })(\(json));"
    }

    /// Updates a page that is already running.
    func capUpdateScript() -> String {
        let data = (try? JSONEncoder().encode([resetClockText])) ?? Data("[\"\"]".utf8)
        let text = String(decoding: data, as: UTF8.self)
        return "window.Enough && window.Enough.setCapState && window.Enough.setCapState(\(capReached ? "true" : "false"), \(text)[0]);"
    }

    func filterScript() -> String {
        EngineResources.filterScript()
    }

    func reconfigureScript() -> String {
        WebBoot.reconfigureScript(
            config: config,
            settings: settings,
            css: EngineResources.hideCSS(),
            seen: seenLibrary.permalinks(),
            homeURL: PlatformCatalog.active.homeURL.absoluteString
        )
    }

    func openSearchURL() -> URL {
        let path = PlatformCatalog.active.searchPath
        return URL(string: "https://www.instagram.com" + path) ?? PlatformCatalog.active.homeURL
    }

    private func updateBlock() {
        isBlocked = CapPolicy.shouldBlock(surface: surface, snapshot: snapshot)
    }

    private func enqueue(_ kind: WebCommand.Kind) {
        commandSerial += 1
        command = WebCommand(id: commandSerial, kind: kind)
    }

    private func instagramURL(_ path: String) -> URL {
        URL(string: "https://www.instagram.com" + path) ?? EnoughConstants.startURL
    }
}

struct URLSessionConfigFetcher: ConfigFetching {
    func fetch(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard RemoteConfigPolicy.accepts(statusCode: http.statusCode, mimeType: http.mimeType, byteCount: data.count) else {
            throw SelectorConfigError.unsafeContent
        }
        return data
    }
}
