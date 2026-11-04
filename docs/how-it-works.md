# How it works

This page follows one day of use from launch to reset.

## 1. Launch

![Launch sequence](diagrams/launch-sequence.svg)

<sub>Source: [diagrams/launch-sequence.excalidraw](diagrams/launch-sequence.excalidraw)</sub>

1. `FeedHost` is created with the app, before the first SwiftUI frame. It builds the `WKWebView` and installs three document-start scripts in this order:
   1. `__ENOUGH_BOOT__`: selectors and toggles
   2. `__ENOUGH_CAP__`: whether the cap is already reached, and the reset time
   3. `filter.js`
2. The cookie store is checked for a session cookie. Only names and domains are looked at, never values. Then the web view loads either `https://www.instagram.com/` or the login page.
3. The ink launch screen stays up until the page sends `ready`, which means the header or feed is on screen. A 3-second fallback removes it if the page is slow. The full page can take much longer on a cold network, and the app doesn't wait for it.

## 2. Filtering the page

As soon as `filter.js` runs, and again whenever the DOM changes:

- **Reels.** Links to `/reels/` are hidden, and the Reels tab's slot is removed so the tab bar has no gap. Reel posts (`/reel/…`) are hidden in the feed.
- **Explore.** The Explore tab is kept but retargeted to `/explore/search/`. A visit to bare `/explore/` is redirected there.
- **Suggestions.** Modules labelled with an exact phrase such as "Suggested for you" are hidden. On Home, any non-ad post that has its own **Follow** button is hidden, because it comes from an account you don't follow.
- **Install prompts.** "Open app", "Use the app" and App Store links are hidden. The navigation policy also cancels `instagram://` and App Store URLs.
- **Ads** are left alone. In the `Enough Personal` build only, they're collapsed.

## 3. Counting a post

![Post counting](diagrams/post-counting.svg)

<sub>Source: [diagrams/post-counting.excalidraw](diagrams/post-counting.excalidraw)</sub>

1. Each feed `article` is observed by an `IntersectionObserver` with a 50% threshold. **Only the Home feed counts.** Profiles, opened posts and search never do.
2. A post must stay at least half on screen for **one second**. Scroll it away sooner and it doesn't count. When the second is up, it's checked again, because parts of a post load late. Any change inside a post re-runs the checks on the whole post.
3. The script finds the post's permalink (`/p/<code>/` or `/reel/<code>/`; both forms are the same post).
4. **Ads, suggestions and your own posts are skipped.** A post with its own Follow button is a suggestion. A post is an ad if it carries a sponsored label ("Sponsored", "Paid partnership", "Ad") or a profile link containing `a_mpk=`. A post is yours if its author link matches the profile link in the site's tab bar. That path is kept in the page's session storage only and never sent to Swift.
5. If the cap is already reached, nothing is sent.
6. Otherwise the page posts `{type: "postViewed", permalink}`.
7. `UsageStore.record` normalises the permalink and ignores any it has seen today. It counts only while `count < cap` and saves to the App Group.
8. The model publishes the new snapshot, and the count ring updates.

Posts seen on an earlier visit are marked `enough-seen` and collapse, so the feed starts with what's new. Posts you count now stay in place. Once the feed moves past your follows (only hidden suggestions after your last post), the page shows **"You're all caught up"** right after the last post you can see. The header, stories and tab bar keep working.

If you lower the cap below today's count, the app simply shows the limit as reached.

## 4. Reaching the cap

![Daily cap](diagrams/daily-cap.svg)

<sub>Source: [diagrams/daily-cap.excalidraw](diagrams/daily-cap.excalidraw)</sub>

When the count reaches the cap:

- Swift's `syncCap` evaluates `capUpdateScript` on the live page and reinstalls the document-start scripts with `reached: true`.
- **Home** replaces its posts with **"You're done for today"** and the reset time. The `html` element gets the class `enough-at-cap`, which hides posts and loading spinners. The site's header, stories row and tab bar stay usable.
- **Profiles and opened posts** stay open. Looking through someone's photos is deliberate and never counts.
- **Reels, Explore and Stories** are covered by a full-screen native overlay with buttons for Messages, Search and Profile.
- **Messages, Search, your Profile and settings** keep working.

`CapPolicy.shouldBlock` holds the rule: when the cap is on and `count >= cap`, the surfaces `feed`, `reels`, `explore` and `stories` are blocked.

## 5. The reset

`DayBoundary` turns "now" into a day key using the reset time, which is 4:00 AM by default. A post seen at 2 AM still belongs to yesterday. The first time `UsageStore` reads usage under a new key, it discards yesterday's seen list and starts from zero. No background task is needed, because rollover happens when the data is read.

The model refreshes every 30 seconds and when the app returns to the foreground, so the feed reopens at the reset time without a relaunch.
