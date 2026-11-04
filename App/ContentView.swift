import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    let host: FeedHost
    // Observe the model itself. FeedHost never publishes, so observing only the host
    // left the launch screen up forever after the page finished loading.
    @ObservedObject private var model: FeedModel
    @State private var showSettings = false

    init(host: FeedHost) {
        self.host = host
        self.model = host.model
    }

    var body: some View {
        ZStack {
            // The web view starts below the status bar. The site pins some headers
            // (Search, Messages) to the very top, and under the status bar they were hidden.
            FeedWebView(model: model, webView: host.webView, bridge: host.bridge, coordinator: host.coordinator)
                .ignoresSafeArea(.container, edges: .bottom)
            if let loadError = model.loadError {
                errorState(loadError)
            } else if model.isBlocked && !model.isLoading && model.surface != .feed {
                // The feed shows its own in-page notice and keeps the site's tabs.
                // Full-screen pages that the cap blocks (stories, reels) still get the overlay.
                DoneOverlay(
                    count: model.snapshot.count,
                    resetClockText: model.resetClockText,
                    onMessages: model.openMessages,
                    onSearch: model.openSearch,
                    onProfile: model.openProfile
                )
            }
            if model.showsInboxTabBar && !model.isLoading && model.loadError == nil {
                VStack(spacing: 0) {
                    Spacer()
                    InboxTabBar(
                        onHome: model.openHome,
                        onSearch: model.openSearch,
                        onProfile: model.openProfile
                    )
                }
                .transition(.opacity)
            }
            if model.isLoading && model.loadError == nil {
                LaunchLoadingView()
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottomTrailing) {
            if !model.isLoading && model.loadError == nil {
                CountButton(count: model.snapshot.count, cap: model.snapshot.cap, capEnabled: model.snapshot.capEnabled) {
                    showSettings = true
                }
                // Sits just above the site's tab bar, clear of its header buttons.
                .padding(.trailing, 14)
                .padding(.bottom, 62)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .onChange(of: model.showsInboxTabBar) { shown in
            // Keep the last inbox row clear of the tab bar.
            host.webView.scrollView.contentInset.bottom = shown ? InboxTabBar.height : 0
        }
        .onAppear {
            model.startLaunchFallback()
            model.refresh()
            #if DEBUG
            // Screenshot hooks for the docs, Debug builds only:
            // `-EnoughOpenSettings` opens Settings, `-EnoughOpen search|messages` opens a tab,
            let arguments = ProcessInfo.processInfo.arguments
            // `-EnoughDemoAtCap` fills today's count with placeholder posts to show the cap.
            if arguments.contains("-EnoughDemoAtCap") {
                for index in 0..<model.snapshot.cap {
                    model.record(permalink: String(format: "p/DEMO%03d", index))
                }
            }
            if arguments.contains("-EnoughOpenSettings") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showSettings = true }
            }
            if let index = arguments.firstIndex(of: "-EnoughOpen"), index + 1 < arguments.count {
                let target = arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if target == "search" { model.openSearch() }
                    if target == "messages" { model.openMessages() }
                }
            }
            #endif
            Task { await model.refreshRemoteConfig() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.refresh()
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            model.refresh()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
            Button("Try again", action: model.retry)
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

enum EnoughBrand {
    static let ink = Color(red: 36.0 / 255.0, green: 51.0 / 255.0, blue: 48.0 / 255.0)
    static let paper = Color(red: 230.0 / 255.0, green: 225.0 / 255.0, blue: 214.0 / 255.0)
    static let uiInk = UIColor(red: 36.0 / 255.0, green: 51.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
}

/// A tab bar for the Messages inbox, which the site shows without one.
/// Plain system symbols, laid out like the site's own bar on the other pages.
struct InboxTabBar: View {
    static let height: CGFloat = 50
    var onHome: () -> Void
    var onSearch: () -> Void
    var onProfile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                tab("house", label: "Home", action: onHome)
                tab("magnifyingglass", label: "Search", action: onSearch)
                tab("paperplane.fill", label: "Messages", selected: true) {}
                tab("person.crop.circle", label: "Profile", action: onProfile)
            }
            .frame(height: Self.height)
        }
        .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
    }

    private func tab(_ symbol: String, label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: selected ? .semibold : .regular))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Today's count as a small progress ring. Tap it for settings.
struct CountButton: View {
    let count: Int
    let cap: Int
    let capEnabled: Bool
    var action: () -> Void

    private var progress: Double {
        guard capEnabled, cap > 0 else { return 0 }
        return min(1, Double(count) / Double(cap))
    }

    private var atCap: Bool { capEnabled && count >= cap }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(atCap ? Color.red : Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: progress)
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.primary)
            }
            .frame(width: 34, height: 34)
            .padding(5)
            .background(.regularMaterial, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(capEnabled ? "\(count) of \(cap) posts today" : "\(count) posts today")
        .accessibilityHint("Opens settings")
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            EnoughBrand.ink
            VStack(spacing: 28) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(EnoughBrand.paper)
                    .frame(width: 148, height: 12)
                Text("Enough")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(EnoughBrand.paper)
                ProgressView()
                    .controlSize(.regular)
                    .tint(EnoughBrand.paper)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Enough")
    }
}

@main
struct EnoughApp: App {
    @StateObject private var host = FeedHost()

    var body: some Scene {
        WindowGroup {
            ContentView(host: host)
        }
    }
}
