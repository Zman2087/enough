# Selectors

Everything Enough knows about Instagram's markup lives in one JSON document, `Sources/FilterEngine/Resources/selectors.json`. When the site changes, update this file. Don't write new script for it.

## The document

```jsonc
{
  "version": 1,
  "hide": {
    "reels":     ["a[href='/reels/']", …],      // Reels entry points
    "explore":   ["a[href='/explore/']", …],    // retargeted to Search, not hidden
    "suggested": ["[data-enough-suggested='1']"],
    "install":   ["a[href^='instagram:']", …]   // "open the app" prompts
  },
  "posts": {
    "containers": ["article"],                   // one per feed post
    "permalink":  ["a[href*='/p/']", "a[href*='/reel/']"],
    "sponsored":  ["[data-sponsored='1']", "a[href*='a_mpk=']", …]   // EXCLUSION list
  },
  "text": {
    "suggested": ["Suggested for you", "Suggestions for you", "Suggested posts"],
    "sponsored": ["Sponsored", "Paid partnership", "Ad"],            // EXCLUSION list
    "install":   ["Open app", "Use the app", …]
  }
}
```

- **Text labels are matched exactly.** They're compared against an element's whole visible text, not searched for inside it. A caption that contains the words "Suggested for you" isn't hidden.
- **Sponsored entries are an exclusion list.** They mark posts that must *not* be hidden (in the App Store build) and must *not* be counted. They're never copied into the hide rules.

## Keep two copies in sync

The same JSON is embedded in `SelectorConfig.bundledJSON` as a fallback. `SelectorConfigTests` fails if the two differ, so edit both.

## Validation

`SelectorConfigValidator` runs on the bundled document and on every remote document. It rejects:

- an unknown `version`
- selectors that are too broad: `*`, `html`, `body`
- anything that looks like script or CSS injection: `<script`, `javascript:`, `{`, `}`, `url(`, `@import`
- a document with **no ad exclusions**, which stops a remote document from quietly making ads countable or hideable

If validation fails, the bundled selectors stay in use.

## Remote updates

In Settings you can enter an optional **remote selector URL**. It must be `https`. Enough downloads it, checks the HTTP status and MIME type, decodes it as a selector document and validates it. The bytes are never evaluated as code.

## When Instagram's markup changes

1. Open a Debug build. Web inspection is on for iOS 16.4 and later. Then inspect the page from Safari → Develop → Simulator.
2. Find the new selector or label.
3. Update `selectors.json` **and** `SelectorConfig.bundledJSON`.
4. Add or update a fixture in `js-tests/fixtures/` that reproduces the new markup, and add a test in `js-tests/filter.test.js`.
5. Run `make test`.

If the fix truly needs new logic in `filter.js`, it ships in an app update, never as remote code.
