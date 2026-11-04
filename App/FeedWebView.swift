import FilterEngine
import SwiftUI
import WebKit

enum WebTiming {
    static let launched = Date()
}

/// Builds the single web view at process start so the first navigation is already underway
/// before SwiftUI asks for the view.
/// Main-actor isolated because it constructs the main-actor `FeedModel`.
@MainActor
final class FeedHost: ObservableObject {
    let model: FeedModel
    let webView: WKWebView
    let bridge = FeedWebView.ScriptBridge()
    let coordinator: FeedWebView.Coordinator

    init() {
        _ = WebTiming.launched  // start the launch clock now, not at first read
        let model = FeedModel.makeShared()
        self.model = model
        coordinator = FeedWebView.Coordinator(model: model, bridge: bridge)
        webView = FeedWebView.build(model: model, bridge: bridge)
        webView.navigationDelegate = coordinator
        coordinator.webView = webView
    }
}

/// Shows instagram.com in the signed-in mobile site.
/// The cookie store is the persistent default store, so the session survives relaunch.
/// Main-frame navigations stay on instagram.com. Subframes are allowed so ads can load.
struct FeedWebView: UIViewRepresentable {
    @ObservedObject var model: FeedModel
    let webView: WKWebView
    let bridge: ScriptBridge
    let coordinator: Coordinator

    func makeCoordinator() -> Coordinator {
        coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.bridge.owner = context.coordinator
        if webView.scrollView.refreshControl == nil {
            let refresh = UIRefreshControl()
            refresh.addTarget(context.coordinator, action: #selector(Coordinator.refreshPulled), for: .valueChanged)
            webView.scrollView.refreshControl = refresh
        }
        return webView
    }

    @MainActor
    static func build(model: FeedModel, bridge: ScriptBridge) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        // App-bound domains are intentionally off. Instagram serves ads from other
        // hosts, and limiting every navigation to instagram.com would drop those frames.
        configuration.limitsNavigationsToAppBoundDomains = false
        // Videos play in place in the feed, as in the native app. Without this, iOS opens
        // every video full screen. Muted feed videos may start on their own, as on the site.
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let controller = configuration.userContentController
        controller.add(bridge, name: EnoughConstants.messageHandlerName)
        installScripts(on: controller, model: model)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = MobileSafari.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.bouncesZoom = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.decelerationRate = .normal
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = .systemBackground
        }
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        FormAccessory.remove(from: webView)
        loadInitial(in: webView)
        return webView
    }

    static func loadInitial(in webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let hints = cookies.map { cookie in
                CookieHint(name: cookie.name, domain: cookie.domain, hasValue: !cookie.value.isEmpty)
            }
            let url = StartDestination.url(hasSession: StartDestination.hasSession(hints))
            DispatchQueue.main.async {
                guard NavigationPolicy.decide(url: url) == .allow else { return }
                webView.load(URLRequest(url: url))
            }
        }
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(model.command, on: webView)
        context.coordinator.syncCap(on: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: EnoughConstants.messageHandlerName)
        coordinator.webView = nil
    }

    @MainActor
    private static func installScripts(on controller: WKUserContentController, model: FeedModel) {
        controller.removeAllUserScripts()
        let boot = WKUserScript(
            source: model.bootScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let filter = WKUserScript(
            source: model.filterScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let cap = WKUserScript(
            source: model.capScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(boot)
        controller.addUserScript(cap)
        controller.addUserScript(filter)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: FeedModel
        let bridge: ScriptBridge
        weak var webView: WKWebView?
        private var handledCommandID = 0
        private var pushedCap: (reached: Bool, resetText: String)?
        private var refreshing = false

        @MainActor
        init(model: FeedModel, bridge: ScriptBridge) {
            self.model = model
            self.bridge = bridge
            super.init()
            bridge.owner = self
        }

        func loadInitialPage(in webView: WKWebView) {
            FeedWebView.loadInitial(in: webView)
        }

        @objc func refreshPulled() {
            refreshing = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard let webView else { return }
            loadInitialPage(in: webView)
        }

        @MainActor
        func apply(_ command: WebCommand?, on webView: WKWebView) {
            guard let command, command.id != handledCommandID else { return }
            handledCommandID = command.id
            switch command.kind {
            case .load(let url):
                guard NavigationPolicy.decide(url: url) == .allow else { return }
                webView.load(URLRequest(url: url))
            case .loadInitial:
                loadInitialPage(in: webView)
            case .reconfigure:
                FeedWebView.installScripts(on: webView.configuration.userContentController, model: model)
                webView.evaluateJavaScript(model.reconfigureScript(), completionHandler: nil)
            case .navigate(let path, let fallback):
                // Switch page inside the site (instant). Load the URL if the engine isn't there.
                let literal = String(data: (try? JSONEncoder().encode(path)) ?? Data("\"/\"".utf8), encoding: .utf8) ?? "\"/\""
                webView.evaluateJavaScript(
                    "!!(window.Enough && window.Enough.navigate && window.Enough.navigate(\(literal)));"
                ) { result, _ in
                    if (result as? Bool) != true, NavigationPolicy.decide(url: fallback) == .allow {
                        webView.load(URLRequest(url: fallback))
                    }
                }
            case .openProfile:
                webView.evaluateJavaScript(
                    "window.Enough && window.Enough.openProfile && window.Enough.openProfile();",
                    completionHandler: nil
                )
            }
        }

        /// Sends the cap state to the page when it changes, and refreshes the document-start
        /// script so the next page load starts with the right state instead of flashing posts.
        @MainActor
        func syncCap(on webView: WKWebView) {
            let current = (reached: model.capReached, resetText: model.resetClockText)
            if let pushedCap, pushedCap == current { return }
            pushedCap = current
            FeedWebView.installScripts(on: webView.configuration.userContentController, model: model)
            webView.evaluateJavaScript(model.capUpdateScript(), completionHandler: nil)
        }

        func receive(_ message: WKScriptMessage) {
            guard message.name == EnoughConstants.messageHandlerName else { return }
            // Only the injected scripts may talk to Swift. They run in the main frame only,
            // so subframes (ads, about:blank, srcdoc) are ignored. The frame's origin must be
            // https instagram.com; the navigation policy's about: allowance does not apply here.
            let frame = message.frameInfo
            let origin = frame.securityOrigin
            guard frame.isMainFrame,
                  origin.protocol == "https",
                  NavigationPolicy.isInstagramHost(origin.host) else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            let model = self.model
            Task { @MainActor in
                switch type {
                case "postViewed":
                    if let permalink = body["permalink"] as? String {
                        model.record(permalink: permalink)
                    }
                case "route":
                    if let path = body["path"] as? String {
                        model.updateRoute(path: path)
                    }
                case "caughtUp":
                    model.noteCaughtUp(true)
                case "hasUnseen":
                    model.noteCaughtUp(false)
                case "ready":
                    model.noteReady()
                case "firstPost":
                    let ms = (body["ms"] as? NSNumber)?.doubleValue ?? 0
                    model.noteFirstPost(pageMilliseconds: ms)
                default:
                    break
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // instagram:// and App Store links are cancelled in every frame, including ads.
            if NavigationPolicy.isAppHandoff(url) {
                decisionHandler(.cancel)
                return
            }
            // A new window (target=_blank) is pulled back into this view when it stays on instagram.com.
            if navigationAction.targetFrame == nil {
                if NavigationPolicy.decide(url: url) == .allow {
                    webView.load(URLRequest(url: url))
                }
                decisionHandler(.cancel)
                return
            }
            // Only the main frame is limited to instagram.com. Ad frames stay loadable.
            if navigationAction.targetFrame?.isMainFrame == false {
                decisionHandler(.allow)
                return
            }
            decisionHandler(NavigationPolicy.decide(url: url) == .allow ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if refreshing {
                refreshing = false
                webView.scrollView.refreshControl?.endRefreshing()
            }
            Task { @MainActor in
                webView.evaluateJavaScript(model.capUpdateScript(), completionHandler: nil)
                model.noteFinishedLoading()
                if let url = webView.url {
                    model.updateRoute(url: url)
                }
            }
        }

        /// iOS can end the page's process, for example under memory pressure while videos
        /// play. The web view is then blank (black in dark mode), so load the page again.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("Enough: web content process ended; reloading")
            if webView.url != nil {
                webView.reload()
            } else {
                loadInitialPage(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        private func reportFailure(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            Task { @MainActor in
                model.noteFailedLoading()
            }
        }
    }

    final class ScriptBridge: NSObject, WKScriptMessageHandler {
        weak var owner: Coordinator?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            owner?.receive(message)
        }
    }
}

/// Removes the up / down / done bar WebKit adds above the keyboard for web form fields.
/// The site's own fields don't need it, and the native app has no such bar.
/// Done by giving the web view's content view a subclass whose `inputAccessoryView` is nil.
enum FormAccessory {
    private static let subclassName = "EnoughNoAccessoryContentView"

    static func remove(from webView: WKWebView) {
        guard let content = webView.scrollView.subviews.first(where: {
            String(describing: type(of: $0)).hasPrefix("WKContent")
        }) else { return }
        guard let subclass = subclass(of: type(of: content)) else { return }
        object_setClass(content, subclass)
    }

    private static func subclass(of base: AnyClass) -> AnyClass? {
        if let existing = NSClassFromString(subclassName) { return existing }
        guard let made = objc_allocateClassPair(base, subclassName, 0) else { return nil }
        let block: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
        let imp = imp_implementationWithBlock(block)
        let selector = #selector(getter: UIResponder.inputAccessoryView)
        guard let method = class_getInstanceMethod(UIResponder.self, selector) else { return nil }
        class_addMethod(made, selector, imp, method_getTypeEncoding(method))
        objc_registerClassPair(made)
        return made
    }
}
