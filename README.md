# Ode

A Mac browser built for people moving from Arc, and for the coding agents they work with.

Ode is open source under the [Mozilla Public License 2.0](LICENSE).

## Get Ode

Visit [odebrowser.com](https://odebrowser.com/) for downloads and current availability.
Ode requires an Apple silicon Mac with macOS 26.1 or later.
See the [installation guide](HelpCenter/docs/getting-started/install-and-update-mac.md) for setup and updates.

## An ode to Arc

[Arc](https://arc.net/) showed how personal a browser could feel. Ode is an ode to Arc.

Ode is built from [Crest](https://github.com/pauljoda/Crest), a great open-source browser by Paul Davis and its contributors. Thank you for the foundation.

We also admire [Dia](https://www.diabrowser.com/) and its approach to AI in the browser. Explore their work, try what suits you, and use the browser you enjoy.

Ode is independent, and is not affiliated with or endorsed by Crest, Paul Davis, Arc, Dia or The Browser Company.

## Help and contribute

- Read the [help guides](HelpCenter/docs) or see [Support](SUPPORT.md) for GitHub and private feedback options.
- [Search GitHub issues](https://github.com/swissyai/odebrowser/issues) or [report a bug or request a feature](https://github.com/swissyai/odebrowser/issues/new/choose).
- [Build from source](#build-from-source) or [contribute](CONTRIBUTING.md).

## Features

- Spaces, each its own browsing profile with isolated cookies, history and passwords, and Sub-Spaces that share one profile
- Pinned tabs, favorites, Today tabs, folders, Split View, Peek and Quick Window
- Arc import: Spaces, pinned tabs, favorites, Today tabs, folders, the archive, recent history, saved passwords and sign-ins
- Imports from Chrome, Brave, Dia, Edge and other Chromium browsers, Safari, Firefox and Zen: profiles or Spaces, bookmarks, open and pinned tabs, and history; passwords from Chromium browsers through their Keychain item
- Command Bar with search shortcuts and tab-to-search
- Chromium and WebKit engines; Chrome Web Store extensions on Chromium
- Ad and tracker blocking on every page, on by default, with Off, Balanced and Strict levels, your own filter lists and Block Element; sleeping tabs, memory pressure handling
- Agents: Claude Code, Codex, Pi, OpenClaw, Hermes and any MCP client connect through the bundled `ode-browser` helper, limited to the Spaces the person allows, with gates for sensitive fields, new sites and downloads
- Optional intelligence, off by default: Apple's on-device model, a model on the same Mac, or the person's own ChatGPT plan

Requests Ode has decided against, with the reasons and what to do instead: [Not planned](Documentation/NotPlanned.md).

## Export format

Settings > Advanced > Automatic export writes the workspace to `~/Documents/Ode Export/`, or a folder the person picks, every day and within an hour of a change to Spaces, pinned and saved tabs or folders. Export Now writes one at once. Each export is a folder named for its local time, `yyyy-MM-dd HH.mm.ss`, written under a hidden name and renamed into place; the newest 7 are kept. Passwords, cookies, website data and extensions are never written, and nothing leaves the Mac.

- `Ode Browser Data.json`: `format` (`com.pauldavis.crest.browser-data`), `schemaVersion` (6), `exportedAt` and `spaces`. Each Space holds `name`, `symbol`, `accent`, `folders`, `tabs` (`placement` is `pinned`, `saved` or `current`), `splitGroups`, `archivedTabs`, `history`, `browsingPreferences` and, when it has any, `boosts`: one per `site`, with `isEnabled`, `isDark`, `tintHue` (OKLCH degrees), `tintStrength` (0 to 1), `brightness` and `contrast` (0.5 to 1.5), `font`, `hiddenSelectors` (CSS selectors) and `customCSS`. Times are milliseconds since 1970 and keys are sorted. Import Browser Data reads every schema version back. The `format` identifier is Crest's and is kept so Crest and Ode exports stay interchangeable.
- `Ode Bookmarks.html`: a Netscape bookmark file, one folder per Space with its pinned and saved tabs and folders.
- `Ode History.jsonl`: one JSON object per history address Ode keeps, with `space`, `url`, `title`, `firstVisitedAt`, `lastVisitedAt`, `visitCount` and `visits`, the time of each visit Ode keeps, oldest first. It holds every address within the Space's history retention; `Ode Browser Data.json` holds each Space's newest 5,000.

## Build from source

### Build prerequisites

In addition to the Mac requirements above:

- Xcode with the macOS and iOS 26.1 SDKs or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- .NET SDK pinned by `OdeCore/global.json` (`Scripts/control-plane/install-dotnet.sh`)

See [Contributing](CONTRIBUTING.md#requirements) for the full developer setup.

### Build

```bash
Scripts/bootstrap.sh
open Ode.xcodeproj
```

An isolated WebKit build, with the core's tests:

```bash
Scripts/control-plane/build-experiment.sh /absolute/path/Ode.app
```

The Chromium product packages a prebuilt engine with the Release UI framework; see [the Chromium engine README](CrestEngines/Chromium/README.md) and `Scripts/control-plane/package-chromium-host.py`.

`project.yml` is the source of truth for targets and settings. Run `xcodegen generate` after changing it, then `tools/dev/normalize-pbxproj.py` against the previous project file.

Only Release builds carry the released identifier, `com.odebrowser.ode`. Debug, test and harness builds, `OdeNativeCore` and Chromium review packages run as `com.odebrowser.ode.dev` (and `com.odebrowser.ode.dev.*`): their preferences, `~/Library/Application Support/Ode Dev`, WebKit data, keychain services, agent socket and `Ode Dev Export` folder are their own, the updater is off, and the installed Ode never lists their crash reports.

## Release

```bash
export ODE_ASC_KEY_ID=... ODE_ASC_ISSUER_ID=...   # App Store Connect API key
Scripts/release-ode.sh --check /absolute/output
Scripts/release-ode.sh /absolute/output
```

Fetches the Developer ID profile through the App Store Connect API (the first run registers the bundle identifier and creates it; that takes an Admin or App Manager key), packages the Chromium product, notarizes and staples the app and disk image, and writes a signed Sparkle appcast for `https://odebrowser.com/updates/`. With `ODE_PREVIOUS_UPDATES` set to the previous release's `updates` folder, the appcast keeps the newest 5 releases and their disk images, so people can go back to an earlier version. It publishes nothing; `Scripts/serve-updates-locally.sh /absolute/output` serves the feed on 127.0.0.1 to test an update on this Mac first. With `ODE_DMGBUILD` set to a [dmgbuild](https://github.com/dmgbuild/dmgbuild) executable, the disk image opens on Ode's themed "Drag Ode into Applications" window from `Scripts/disk-image`; without it, the image is a plain folder. iCloud sync and browser passkeys stay off until Ode's iCloud container and Apple's passkey entitlement are granted; `OdeMac/Configuration/Ode-Direct.entitlements` is the entitlement set until then.

## Validate

```bash
Scripts/validate-identity.sh
python3 -m unittest discover -s Scripts/Tests
(cd OdeCore && dotnet test tests/OdeCore.Tests)
```

`validate-identity.sh` fails when a visible string names the base product or the app links to its sites. After cherry-picking an upstream change, run `tools/dev/rename-product-strings.py`.

Debug and review builds include a test harness (`ODE_TEST_HARNESS=1` with an isolated session): the app never activates, keeps its windows off the screens and takes commands on a socket beside the session. These drive it without the screen or the keyboard:

```bash
tools/dev/command-bar-latency.sh /absolute/path/OdeNativeCore.app
tools/dev/launch-safety-e2e.sh /absolute/path/OdeNativeCore.app
tools/dev/reliability-e2e.sh /absolute/path/OdeNativeCore.app
tools/dev/harness-snapshots.sh /absolute/path/OdeNativeCore.app /absolute/output/folder
```

## Source layout

Modules, targets, types and folders use the Ode name. Names the prebuilt Chromium engine binds keep the base name until the engine is rebuilt: the engine's inputs under `CrestEngines/Chromium` and `CrestContracts/include`, the prebuilt content filter's crate in `CrestCore/native/ContentFilter`, the `CrestChromiumUI` frameworks, and the C ABI's `crest_` names. After cherry-picking an upstream change, run `tools/dev/rename-identifiers.py`, regenerate the contracts, then run `xcodegen generate`; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgements

Ode and Crest are released under the Mozilla Public License 2.0. Crest's trademarks remain with their owners; see [TRADEMARKS.md](TRADEMARKS.md).

- [Crest](https://github.com/pauljoda/Crest) by Paul Davis, with contributions from hcbille, Samuel Ji, Avelino, weensy, Patrick and Gustavo Lima. Its engines, core, sidebar, Spaces, importers and agent tools are the base Ode builds on.
- [Chromium](https://www.chromium.org/), Apple's WebKit, Brave's [adblock-rust](https://github.com/brave/adblock-rust), the [.NET runtime](https://github.com/dotnet/runtime), [Sparkle](https://github.com/sparkle-project/Sparkle), the [EasyList](https://easylist.to/) authors and the Unicode Consortium. Licences and notices: [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `ThirdParty/`.

## License

Mozilla Public License 2.0. See [LICENSE](LICENSE), [NOTICE](NOTICE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
