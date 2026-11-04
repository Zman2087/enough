# Development

## Requirements

| To | You need |
| --- | --- |
| Run the tests | Swift 5.9+ and Node 20+ (macOS or Linux) |
| Build and run the app | macOS with Xcode 16+, iOS 16+ simulator or device |
| Regenerate diagrams or the project | Python 3 |

## Commands

```sh
make test                  # everything below except typecheck
make lint-pbxproj          # project file uses only safe unquoted values
make check-release-ads     # PERSONAL_BUILD never reaches Release / main scheme
make check-launch          # launch image isn't mostly transparent
make test-swift            # swift test
make test-js               # npm install + node --test (jsdom)
make typecheck             # xcodebuild both schemes for the simulator

swift test --filter PolicyTests                                  # one Swift test class
swift test --filter PolicyTests/testRoutesMatchTheSharedFixture  # one Swift test
node --test js-tests/filter.test.js                              # one JS file (after npm install)
```

CI (`.github/workflows/ci.yml`) runs the Python checks, `plutil -lint` on the project and `xcodebuild` for both the **Enough** and **Enough Personal** schemes with signing turned off.

## Running the app

1. `open Enough.xcodeproj`
2. Choose the **Enough** scheme. Use **Enough Personal** only for a sideloaded build that hides ads.
3. For a device, set Signing & Capabilities to your team on every target: app, FilterEngine, tests and both extensions. Xcode should register the App Group `group.app.enough.shared` the first time you sign.
4. Run, then log in with your username and password.

If provisioning complains about the Shield extension before Family Controls is approved, remove `EnoughShieldExtension` from the scheme's build list and from the app's Embed Foundation Extensions phase.

### Inspecting the page

Debug builds set `isInspectable = true` on iOS 16.4 and later. Open Safari → Develop → *your simulator* → instagram.com to inspect the DOM and try selectors.

## Debug launch arguments

These exist only in Debug builds (`#if DEBUG`) and are used for documentation screenshots:

| Argument | Effect |
| --- | --- |
| `-EnoughDemoAtCap` | Fills today's count with placeholder entries (`p/DEMO000`…) so the cap state appears without scrolling |
| `-EnoughOpenSettings` | Opens Settings 2.5 s after launch |
| `-EnoughOpen search` / `-EnoughOpen messages` | Opens that tab 2.5 s after launch |

```sh
xcrun simctl launch booted app.enough.ios -EnoughOpen search
```

### Screenshots

1. Use a **test account** that follows nobody. The repo is public, so screenshots must not show other people's posts, names or messages.
2. Fix the status bar so every shot matches:
   ```sh
   xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
   ```
3. Launch with the arguments above, take each shot with `xcrun simctl io booted screenshot <file>.png` and downscale it to about 1000 px tall with `sips -Z 1000`.
4. Put the images in `docs/screenshots/`, then run `xcrun simctl status_bar booted clear`.

`-EnoughDemoAtCap` writes real entries to today's count, so a normal launch afterwards still shows the cap. Reset it by deleting the app or waiting for the reset time.

## Generated files

### Xcode project

`Enough.xcodeproj` is generated. **Don't edit `project.pbxproj` by hand.**

```sh
python3 scripts/generate_xcodeproj.py
```

The script has **hardcoded file lists**. When you add, remove or rename a source or resource file, update those lists first, then regenerate. Unquoted values may only use `[A-Za-z0-9_./-]`, and `make lint-pbxproj` checks this.

### Diagrams

The diagrams in `docs/diagrams/` are described once in `scripts/build_diagrams.py`, and each is written as an editable `.excalidraw` file plus an `.svg` that GitHub shows inline.

```sh
python3 scripts/build_diagrams.py
```

You can also open a `.excalidraw` file at [excalidraw.com](https://excalidraw.com) to edit it by hand. If you do, export the SVG over the old one. A later run of the script will overwrite manual edits, so move them into the script.

### Launch image

```sh
python3 scripts/launch_mark.py          # regenerate
python3 scripts/launch_mark.py --check  # verify (CI)
```

## Things that must stay in sync

- `selectors.json` ↔ `SelectorConfig.bundledJSON`, enforced by a test.
- `Tests/FilterEngineTests/Fixtures/routes.json` is used by **both** the Swift route tests and `js-tests/filter.test.js`. A change to route classification must pass both.
- New source or resource files ↔ the lists in `scripts/generate_xcodeproj.py`.
- `PERSONAL_BUILD` appears only in the `Personal` configuration and the `Enough Personal` scheme.
