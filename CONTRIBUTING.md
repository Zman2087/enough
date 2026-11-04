# Contributing to Enough

Thanks for helping. Enough is a small, focused app: it gives Instagram a stopping point. Contributions that make that work better are very welcome, including bug fixes, selector updates, accessibility, performance, tests and docs.

## Before you start

- **Bugs:** open an issue with your iOS version, the device or simulator, what you expected and what happened. If the site's markup changed, include the relevant DOM snippet with personal content removed.
- **Features:** open an issue to discuss it first. Enough deliberately does *less*, and some reasonable-sounding features conflict with the [hard rules](#hard-rules).
- **Security or privacy issues:** don't open a public issue. See [privacy-and-compliance.md](docs/privacy-and-compliance.md#reporting-a-privacy-or-security-issue).

## Setup

```sh
git clone https://github.com/Zman2087/enough.git
cd enough
make test
```

Swift 5.9+ and Node 20+ are enough to run the tests. To build the app you need Xcode 16+ on macOS. See [docs/development.md](docs/development.md).

## Hard rules

Pull requests that break any of these can't be merged. The reasons are in [Key Design Decisions](docs/key-design-decisions.md).

1. **instagram.com only.** Only `https://instagram.com` and its subdomains may load in the main frame.
2. **No remote code.** Never download, `eval` or inject remote JavaScript. Markup fixes go in selector JSON, and logic changes ship in the app bundle.
3. **Ads stay visible in the App Store build and never count.** Sponsored selectors are an exclusion list. `PERSONAL_BUILD` belongs only to the `Personal` configuration and the `Enough Personal` scheme.
4. **No private APIs, scraping, exporting or reading cookies or passwords.** The only stored data is settings, post shortcodes (today's count, deleted at reset, plus a capped list that keeps seen posts collapsed) and an optional salted PIN digest.
5. **No "Insta"/"gram" naming and no Instagram logo** in the app's own interface.
6. **FilterEngine stays platform-independent.** No UIKit or WebKit imports in `Sources/FilterEngine/`.
7. **Don't hand-edit `project.pbxproj`.** Update `scripts/generate_xcodeproj.py` and regenerate.

## Making a change

1. Create a branch from `main`: `git checkout -b fix/short-description`.
2. Make the change, with tests:
   - Swift logic → `Tests/FilterEngineTests/`
   - Page behaviour → a fixture in `js-tests/fixtures/` and a test in `js-tests/filter.test.js`
   - Route classification → `Tests/FilterEngineTests/Fixtures/routes.json`, which both suites run
3. If you added, removed or renamed files, update `scripts/generate_xcodeproj.py` and run it.
4. If you changed a diagram, edit `scripts/build_diagrams.py` and run it.
5. Run `make test`. On a Mac, also run `make typecheck`.
6. Open a pull request.

### Selector-only fixes

This is the most common contribution. Update **both** `Sources/FilterEngine/Resources/selectors.json` and `SelectorConfig.bundledJSON`, and add a fixture reproducing the new markup. See [docs/selectors.md](docs/selectors.md).

## Style

- **Swift:** follow the surrounding code. Prefer small value types and pure functions in FilterEngine, and keep comments to the *why*.
- **JavaScript:** plain ES2017 or later, no dependencies, no build step. `filter.js` must keep working both in the web view and under Node (UMD exports).
- **Commits:** short imperative subject ("Hide the new suggestions module"), with a body if the reason isn't obvious.
- **Docs:** if you change behaviour, update the relevant page in `docs/`.

## Pull request checklist

- [ ] `make test` passes
- [ ] New behaviour has tests (Swift and/or jsdom)
- [ ] No hard rule is broken
- [ ] `selectors.json` and `SelectorConfig.bundledJSON` match, if either changed
- [ ] `scripts/generate_xcodeproj.py` updated and the project regenerated, if files were added or renamed
- [ ] Docs updated, if behaviour changed
- [ ] Screenshots, if any, show only a test account with no other people's content

## Code of conduct

Be kind and constructive. Assume good intent, critique code rather than people, and help newcomers. Harassment of any kind isn't tolerated, and maintainers may remove comments or contributors that break this.
