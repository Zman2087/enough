# Key Design Decisions

This is the KDD log. Each entry records a decision that shapes the app, the options considered and the reasons for the choice. If you want to reverse one, open an issue that explains what changed.

Format: **Context** → **Decision** → **Why** → **Trade-offs**.

---

## KDD-01: Wrap the website instead of modifying the native app

**Context.** The native Instagram app can't be changed. On iOS, the only ways to put limits on it are Screen Time (all or nothing, and easy to dismiss) or deleting it.

**Decision.** Ship a separate app that shows `instagram.com` in a `WKWebView` and enforces limits in the page.

**Why.** The mobile website has everything worth keeping: the feed, DMs, search, profiles and posting. A web view lets us see the DOM, so we can count posts and close the feed at a precise point, not just lock the app after N minutes.

**Trade-offs.** The website's markup changes without notice (handled by KDD-06). The site can slightly lag the native app in features. Users log in again inside Enough because its cookie store is separate from Safari's.

## KDD-02: Count posts, not minutes

**Context.** Time limits punish slow, deliberate use and do nothing about fast, mindless scrolling.

**Decision.** The limit is a **number of posts per day** (30 by default, 1–500 in settings). A post counts once, the first time at least 50% of it is on screen. It's identified by its permalink, so scrolling back up doesn't count it again.

**Why.** A post count maps to the real problem, the endless supply. It's predictable ("30 posts is enough"), and it doesn't change with reading speed.

**Trade-offs.** A post skimmed at half visibility counts the same as one read carefully. We accept that, because a stricter measure (time spent on each post) would be easy to game and feel invasive.

## KDD-03: The page observes, Swift decides

**Context.** Logic could live entirely in JavaScript or entirely in Swift.

**Decision.** `filter.js` only *reports* (`postViewed`, `route`, `ready`). Swift owns the count, the cap and which surfaces are blocked (`CapPolicy`), and pushes the cap state back to the page.

**Why.** State in the page is lost on every navigation and can be cleared by the site. Swift state is stored and unit-tested, and it's shared with the extensions through the App Group. Keeping decisions in Swift also makes them testable without a browser.

**Trade-offs.** Two languages, plus a bridge to keep in sync. A shared route fixture (`Tests/FilterEngineTests/Fixtures/routes.json`) is run by both test suites so they can't drift apart.

## KDD-04: The cap closes the feed, not the app

**Context.** The first design covered everything with a full-screen "done" overlay at the cap, which also blocked DMs and search.

**Decision.** At the cap, only the endless surfaces close: **Home, Reels, Explore and Stories**. Home shows an in-feed notice where the posts were, and the site's header and tab bar stay. Messages, Search and Profile keep working. Single post pages are covered too, so the cap can't be bypassed by tapping into a post.

**Why.** The goal is to end doomscrolling, not to cut people off from friends. Closing the whole app pushes people back to the native app, which defeats the point.

**Trade-offs.** More states to get right, for example cap-hiding on post pages and hiding the site's loading spinner, which otherwise spins forever at the cap.

## KDD-05: Following-only home feed

**Context.** When you've seen everything from people you follow, Instagram fills the feed with recommended posts. That's where the scroll becomes endless.

**Decision.** On Home, hide suggestion modules (matched by exact labels) and any non-ad post that has its own **Follow** button, since that means you don't follow the account. When nothing unseen is left, show **"You're all caught up"**.

**Why.** "Caught up" is a natural stopping point. Removing suggestions gives it back.

**Trade-offs.** It relies on visible labels and buttons, which change with the site (see KDD-06). The Following view (`?variant=following`) is left alone because it is already following-only.

## KDD-06: Selectors are data and never code

**Context.** Instagram's markup changes often, and fixing it by downloading new JavaScript would break App Store Guideline 2.5.2 and be a security risk.

**Decision.** Every CSS selector and visible label lives in `selectors.json`. An optional remote URL can supply an updated document. It must be HTTPS JSON and is run through `SelectorConfigValidator`, which rejects:

- script
- CSS injection
- selectors that are too broad
- missing ad exclusions
- unknown schema versions

The executable script always ships in the app bundle.

**Why.** This allows fast fixes without an app update and keeps everything that runs on the page inside the binary Apple reviewed.

**Trade-offs.** Some breakages need logic, not just a selector, and those must wait for an app release.

## KDD-07: Ads stay visible and never count

**Context.** People want ads gone. But hiding a platform's ads in a public App Store app invites rejection and takedown, and it's the platform's business model.

**Decision.** In the App Store build, ads are **left visible** and **excluded from the count**. Sponsored selectors are an exclusion list and must never end up in the hide rules, which the validator enforces. Only the separate `Enough Personal` scheme (`PERSONAL_BUILD`) collapses them, and CI fails if that flag reaches Release.

**Why.** Users shouldn't spend their daily posts on ads, and the App Store build stays defensible.

**Trade-offs.** Ads still take up screen space in the shipping app.

## KDD-08: Main frame limited to instagram.com; subframes allowed

**Context.** A web-view wrapper can be used to browse anywhere, which an App Store reviewer will ask about. Instagram also tries to hand you off to the native app.

**Decision.** `NavigationPolicy` allows only `https://instagram.com` and its subdomains in the main frame. It cancels:

- `http:` and `javascript:` URLs
- `instagram://` and App Store links
- Facebook login

Subframes may load, and app-bound domains are off, so ad frames still render (KDD-07).

**Why.** This keeps the app focused on one job and stops it from bouncing the user into the native app's endless feed.

**Trade-offs.** "Continue with Facebook" login doesn't work. Users log in with their username and password.

## KDD-09: Store almost nothing

**Context.** Counting posts means remembering which ones you've seen.

**Decision.** Store only today's settings and the **post shortcodes** already in each permalink (`p/AbC123`). They are kept in the App Group, capped at 2,000 and deleted at the daily reset. Enough stores no usernames, captions, images or cookies, and nothing leaves the device.

**Why.** Least data is the best privacy policy, and it keeps the App Store privacy label at "Data Not Collected".

**Trade-offs.** There's no history or statistics across days. That's deliberate, and any future stats would have to be opt-in and stay on the device.

## KDD-10: A reset time instead of midnight

**Context.** Many people scroll late at night. A midnight reset hands out a fresh 30 posts at 12:01 AM.

**Decision.** The day rolls over at a user-chosen time, 4:00 AM by default. `DayBoundary` computes the day key, and that handles daylight-saving changes.

**Why.** Late-night scrolling then counts against the same day.

## KDD-11: Look like the real app

**Context.** Early versions added their own chrome: a top bar, a full-screen "done" page and custom tabs. They felt clunky, and people went back to the native app.

**Decision.** The site runs full screen with its own header and tab bar. Enough adds only:

- a small count ring, which opens settings when tapped
- in-feed notices styled like the site's own
- a tab bar on Messages, where the mobile site has none

The keyboard's form-accessory bar is removed so typing feels native.

**Why.** If Enough feels worse than the native app, people won't keep using it.

**Trade-offs.** It depends on the site's layout, for example where its tab bar sits and which headers are pinned.

## KDD-12: Build the web view before SwiftUI asks for it

**Context.** A cold start spent seconds on a blank screen while SwiftUI created the view, the view created the web view and only then did the network request start.

**Decision.** `FeedHost` creates the `WKWebView` and starts the first load when the app starts. The launch screen comes down on a `ready` message from the page, which arrives as soon as the header or feed exists, with a 3-second fallback. It doesn't wait for `didFinish`.

**Why.** `didFinish` can take 20 seconds on Instagram, but the page can be used long before that.

## KDD-13: FilterEngine is platform-independent

**Decision.** All rules that can be tested live in a Swift package with no UIKit or WebKit dependency. They are compiled both as a SwiftPM library and as the app's framework.

**Why.** `swift test` runs in seconds on any Mac or Linux CI machine without Xcode or a simulator. The same code will power the Safari extension and the Screen Time shield.

## KDD-14: The Xcode project is generated

**Decision.** `Enough.xcodeproj` is produced by `scripts/generate_xcodeproj.py` from hardcoded file lists. Nobody edits it by hand. `lint_pbxproj.py` rejects unquoted values that newer Xcode versions fail to parse.

**Why.** This avoids merge conflicts in `project.pbxproj` and the slow, silent damage that hand edits cause.

**Trade-offs.** Adding a file means updating the generator. [CONTRIBUTING.md](../CONTRIBUTING.md) covers this.
