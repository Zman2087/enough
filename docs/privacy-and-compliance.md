# Privacy & compliance

These rules are part of the product. A change that breaks any of them won't be merged, however useful it is.

## What Enough stores

| Data | Where | How long |
| --- | --- | --- |
| Settings: cap, reset time, toggles, optional selector URL | App Group `group.app.enough.shared` | Until changed |
| Today's day key and the post shortcodes counted today (for example `p/AbC123`), at most 2,000 | App Group | Deleted at the daily reset |
| Shortcodes of posts already shown, at most 4,000, so they stay collapsed next time | App Group | Oldest dropped first; deleted with the app |
| Optional PIN lock: a random salt and a SHA-256 digest, never the PIN itself | App Group | Until the lock is removed or the app is deleted |
| Instagram session | The web view's own cookie store (`WKWebsiteDataStore.default()`) | Managed by WebKit and the site |

Nothing else is stored, and nothing is sent anywhere. The privacy manifest (`App/PrivacyInfo.xcprivacy`) declares no tracking and no data collection. The only required-reason API used is `UserDefaults`, for the App Group (`1C8F.1`).

## What Enough never does

- **Never sees your password.** You log in on Instagram's own page. The app doesn't read or fill form fields.
- **Never reads cookies.** At launch, the app checks only cookie *names and domains* to choose between login and home. Values are never read.
- **Never calls private APIs.** It only loads the public website.
- **Never scrapes, exports or uploads content.** No usernames, captions, images or follower lists are collected.
- **Never runs remote code.** The page script ships in the app bundle. Remote selector updates are validated JSON data and are never passed to `eval` or a `<script>` tag (App Store Guideline 2.5.2).
- **Never hides ads in the App Store build.** Ads stay visible and are excluded from the count. Ad hiding is compiled only into the `Enough Personal` scheme, and CI rejects it anywhere else.

## Navigation rules

- The main frame may load only `https://instagram.com` and its subdomains.
- These are cancelled: `http:`, `javascript:`, `instagram://`, App Store links, and Facebook login (it leaves instagram.com).
- Subframes may load, so ad frames render. App-bound domains are off for the same reason.
- `target=_blank` links that stay on instagram.com open in the same view. Others are dropped.

## Branding

- Nothing in the app's own interface is named "Insta" or "gram", and there's no Instagram logo. The site's own header shows its wordmark because it's the site.
- Enough isn't affiliated with Instagram or Meta, and the README and App Store listing say so.

## Platform entitlements

- The Family Controls entitlement in `Extensions/Shield/EnoughShield.entitlements` stays **commented out** until Apple approves the request. Don't upload a build with it enabled before then.

## App Store review notes

- **Guideline 4.2 (minimum functionality).** The daily cap, the reset, the following-only filter and the on-device counting are functionality beyond the website.
- **Guideline 2.5.2.** No downloaded executable code. See [selectors.md](selectors.md).
- If a reviewer pushes back, don't answer by adding private API calls, scraping or ad removal.

## Reporting a privacy or security issue

Please don't open a public issue. Contact the maintainer through GitHub ([@Zman2087](https://github.com/Zman2087)) and describe the problem. We'll fix it before disclosing.
