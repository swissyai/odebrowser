# Ode distribution

Ode ships one Mac app, Ode, with the Chromium and WebKit engines. It is
distributed directly: signed with Developer ID, notarized by Apple, delivered
as a disk image, and updated through Sparkle 2 from
`https://odebrowser.com/updates/`. There is no Mac App Store build and no
separate WebKit-only download. Keeping one macOS product avoids incompatible
sandbox capabilities, duplicate update behavior, and confusion over which build
supports extensions.

Ode has no iPhone or iPad release process. The Mac app requires Apple silicon
and macOS 26.1 or later; the packaged app and its Sparkle feed take the higher
minimum macOS version required by the engine and the native UI framework.

`Scripts/release-ode.sh` is the whole release. It builds, signs, notarizes and
packages Ode without anyone at the keyboard, writes a signed appcast, and
publishes nothing.

## Prerequisites

```bash
export ODE_ASC_KEY_ID=... ODE_ASC_ISSUER_ID=...   # App Store Connect API key
Scripts/release-ode.sh --check /absolute/output
```

`--check` checks local prerequisites and exits without building. It does not
verify keyed publication, the cached engine's integrity, runtime capabilities,
managed Apple grants or current security fixes. A release needs:

- a Developer ID Application identity for team `WUMLCL8SAZ` in the keychain;
- an App Store Connect API key: its `.p8` file at `ODE_ASC_KEY_PATH` (default
  `~/.appstoreconnect/AuthKey.p8`), its id in `ODE_ASC_KEY_ID`, and the issuer
  id shown above the team keys in `ODE_ASC_ISSUER_ID`;
- the .NET SDK named in `OdeCore/global.json`;
- `xcodebuild`, `xcodegen`, `hdiutil`, `ditto`, and Xcode's `notarytool` and
  `stapler`;
- the GitHub CLI, unless the engine is already cached or `ODE_CHROMIUM_APP`
  names a `Chromium.app` to package instead;
- the Sparkle private key in the login keychain, where `generate_appcast` reads
  it. The matching public key is `SUPublicEDKey` in
  `OdeMac/Configuration/Ode-Info.plist`.

Sparkle's `generate_appcast` comes from `ODE_SPARKLE_BIN`, or from the Sparkle
package Xcode resolves into DerivedData; when neither has it yet, the build
resolves it.

The API key does all of Apple's account work. `Scripts/asc-developer-id-profile.py`
registers the `com.odebrowser.ode` bundle identifier and creates the "Ode
Developer ID" provisioning profile on the first run and reuses them later;
that needs a key with the Admin or App Manager role, while notarization alone
works with a Developer key. The same key authenticates `notarytool`.

## Read-only preflight

```bash
python3 Scripts/release-preflight.py --online > /absolute/evidence/preflight.json
```

This performs provider GETs for the exact checkout's engine release and its
small provenance/checksum sidecars; it never downloads an engine, builds,
launches an app or changes an Apple account. It compares the full engine key,
pin, upstream revision, performance configuration, SDK/PGO recipe and archive
digest. A missing, draft, incomplete or inconsistent publication fails closed.
The engine key includes the four C contract headers as well as patches,
overlay, host header and build inputs. Changing any needs a matching newly
published engine before release integration.

To reproduce a recorded inspection without provider access:

```bash
python3 Scripts/release-preflight.py \
  --release-metadata /absolute/evidence/release.json \
  --provenance /absolute/evidence/engine.zip.json \
  --checksum /absolute/evidence/engine.zip.sha256
```

Add `--archive /absolute/engine.zip` to hash an existing archive. Metadata-only
success does not check archive bytes. Neither mode verifies code signatures,
notarization, provenance attestation or runtime behavior; provider digests and
sidecars are consistency evidence, not an independent security attestation.
Exit zero means the requested publication evidence matched, **not** permission
to release: `release_ready` remains false. The report separately records partial
local-tool prerequisites, direct entitlement declarations, untested runtime and
unassessed security freshness. Declaration is not a signed-package grant.

The exact packaged dual-engine app still needs isolated acceptance of origin
redirects, popups/new windows, engine transitions, revocation and private/locked
Space ownership. Its agent page operations remain unavailable with a Chromium
or mixed roster, including resident WebKit tabs; screenshots always refuse.
Use `session_capabilities` on the connected MCP session for advisory eligibility,
not the static tool catalog. Agent cancellation is cooperative: queued work and
subsequent checkpoints stop, but submitted engine input, scripts or navigation
may continue and are never rolled back. A lost response or timeout has an
unconfirmed outcome, not permission to blindly repeat a mutating action.

For in-flight WebKit page calls, Stop and Space revocation are rechecked before
each new script or input submission. Restoring Space access does not restore
a revoked claim for a running call, including its optional follow-up report.
An explicit negative input receipt is a refusal; a missing or late receipt is
unconfirmed, even when the input has already changed the page. These safeguards
do not establish automation support for the standard mixed-engine package.

A release operator must also verify the final package's actual engine identity,
managed entitlements, install/update/interruption/rollback behavior and supported
OS/WebKit updates. Assign a security-update owner to compare the exact shipped
engine and backports with vendor advisories and to own urgent updates. A newer
Chrome announcement alone establishes neither a vulnerability nor freshness in
an installed Ode copy. iCloud sync and browser passkeys require Apple's managed
grants and signed-package acceptance; Ode's origin-bound Keychain passwords are
a separate feature.

## Building a release

```bash
Scripts/release-ode.sh /absolute/output
```

The output folder must not exist yet. The build number is `ODE_BUILD_NUMBER`,
or the UTC date and time as `YYYYMMDDHHMM`, so each release outranks the last.
The marketing version comes from `Config/Version.xcconfig`; set it with
`Scripts/set-version.sh --release X.Y.Z` for a new release line or
`Scripts/set-version.sh --patch` for a fix. Builds reuse
`~/Library/Developer/Xcode/DerivedData/Ode-Release` unless
`ODE_RELEASE_DERIVED_DATA` names another folder.

The script:

1. downloads the Chromium engine for the checkout's engine key from the GitHub
   releases of upstream Crest (`pauljoda/Crest`), checks its SHA-256 checksum,
   and caches it in `~/Library/Caches/Ode-release/<engine tag>`;
   `ODE_CHROMIUM_APP` skips the download;
2. fetches the Developer ID provisioning profile for team `WUMLCL8SAZ` through
   the App Store Connect API, creating it when needed;
3. writes out `OdeMac/Configuration/Ode-Direct.entitlements` with the team's
   prefix;
4. builds the native core (`OdeCore.Native`) and `CrestChromiumUIProduct`,
   and packages them with the engine through
   `Scripts/control-plane/package-chromium-host.py --product --distribution
   --without-cloudkit` as `Ode.app`, signed with the Developer ID identity,
   hardened runtime, and those entitlements;
5. verifies the app's signature, bundle identifier, and build number;
6. notarizes and staples the app, then checks it with Gatekeeper;
7. builds an `Ode` disk image holding the app and an `Applications` link, then
   signs, notarizes and staples it;
8. with `ODE_PREVIOUS_UPDATES` naming the previous release's `updates`
   folder, carries its `appcast.xml` and every disk image, delta and release
   note it names into this release's `updates` folder (an item whose disk
   image is missing stops the release);
9. runs Sparkle's `generate_appcast` over the `updates` folder with the download
   prefix `https://odebrowser.com/updates/`, keeping the newest
   `ODE_FEED_VERSIONS` releases (5 by default) and writing deltas to the newest
   from the ones before it, and signs the appcast with the key in the login
   keychain;
10. moves every file the appcast no longer names into `updates/old_updates/`.

The output folder then holds:

- `Ode.app`;
- `updates/Ode-<version>-<build>.dmg`, and the disk images of the earlier
  releases the feed keeps;
- `updates/*.delta`;
- `updates/appcast.xml`;
- `updates/old_updates/`, which is never published.

The feed keeps five releases so that Ode can offer to go back to any of them
(about a month at a weekly rhythm) while the server holds about 1 GB of disk
images. Without `ODE_PREVIOUS_UPDATES` the feed lists the new release alone.

The script uploads and publishes nothing. Publishing the `updates` folder to
`https://odebrowser.com/updates/` is a separate, deliberate step. Installed
copies read `https://odebrowser.com/updates/appcast.xml` (`SUFeedURL`), so an
update reaches people only once both the disk image and the new appcast are
there.

The script writes only the stable feed. The app's other update channels read
their own appcasts under the same folder, such as `appcast-development.xml`;
no Ode process writes those.

## Testing an update on this Mac

```bash
Scripts/serve-updates-locally.sh /absolute/release/output
```

serves a copy of the release's feed at `http://127.0.0.1:8787/` until
Control-C, and prints the `defaults write` command that points the installed
Ode at it and the `defaults delete` command that undoes it; it runs neither.
The copy's downloads point at the local server, it has no phased rollout, and
it is signed again with the release's key (from the login keychain, or
`--ed-key-file`), because Ode accepts only a feed signed with that key. The
release folder is left as it is, and nothing leaves the Mac. The installed
copy takes an item only when both its build number and its marketing version
are newer than its own; the script lists which items qualify.

Ode reads the hidden `SUFeedURL` preference only when it names an `http`
address on this Mac (`127.0.0.1`, `localhost` or `::1`), on every channel,
and Settings > About shows that a test feed is in use, with a button that
goes back to the published feed. Ode 0.8.80 and earlier read the same
preference through Sparkle, on the Stable channel only.

## Entitlements

`OdeMac/Configuration/Ode-Direct.entitlements` is the entitlement set for
direct releases until Ode's iCloud container and Apple's browser passkey
entitlement are granted. It carries camera, microphone, location, and the
`com.odebrowser.ode` keychain access group, and omits iCloud, push, and
`com.apple.developer.web-browser.public-key-credential`. Packaging with
`--without-cloudkit` accepts a profile that grants the app identity and
keychain but no CloudKit container, so iCloud sync and browser passkeys stay
off in these builds. `OdeMac/Configuration/Ode.entitlements`, which
`project.yml` uses by default, holds the full set.

## Update behavior

Released copies check for, download and install updates on their own
(`SUEnableAutomaticChecks` and `SUAutomaticallyUpdate` are on); a product
package built without `--automatic-updates` turns both off. A download
Sparkle starts by itself stays out of the sidebar until it is ready, then the
card offers only **Restart to update**, because the next quit installs it
anyway. The first launch of a newer build lists the public release-note
entries the build before it did not carry, from the catalog it bundles.

Going back to an earlier version reads the signed feed again, lists the older
builds this Mac can run on the chosen channel, downloads the chosen disk
image, and checks its EdDSA signature before mounting it. The app inside must
carry the same bundle identifier and Developer ID team as the running copy, be
notarized, and be the build the feed named. Ode then quits through its usual
quit, a separate process swaps the bundles once Ode has exited (putting the
installed one back if the swap fails), records the build it left as
Sparkle's skipped version so it is not installed again until a newer one is
out, and opens Ode. Sparkle refuses downgrades, so it takes no part. Data
stays in place: the session store refuses a newer storage or journal version
and asks for an update rather than changing anything, and the app's
`OdeSessionStorageVersion` and `OdeSessionJournalVersion` let the sheet warn
before going back to a build that reads older versions, or to an older
Chromium engine.

When a person chooses Download Update from an available update card, Ode ends
that undownloaded offer and asks Sparkle to check the selected channel again.
It downloads the newly selected compatible build without an extra click. A
failed or cancelled check does not install the old offer. Sparkle continues to
own signature verification, channel filtering, version selection, and installation.
Already downloaded, extracting, or prepared updates retain Sparkle's existing
installation lifecycle.

The Sparkle key should be rotated deliberately, with the old signing path
retained long enough to update installed copies safely.

## Removing behavior

Anything that owns the person's data, such as Spaces, history, passwords,
sessions or imports, gets an export path and one stable release of notice
before it is removed. Every removal, of data or not, ships with a `removed`
release note.

A `removed` entry in `Documentation/ReleaseNotes.json` has two fields beyond
`category` and `message`:

```json
"<entry-id>": {
  "category": "removed",
  "message": "<What is gone>.",
  "replacement": "<What to use instead, or: no replacement>",
  "removedIn": "<X.Y.Z>"
}
```

The message says what is gone. `replacement` names what to use instead, or
reads exactly `no replacement`. `removedIn` is the first version without the
behavior: the version the removing commit sets, which
`Scripts/check-version.sh --fix-commit` requires, and never later than the
checkout's own version.

## Verify a release

About > Credits and Licenses exposes the bundled notices offline and links
Source Code to `https://github.com/swissyai/odebrowser/tree/v<VERSION>`, using
the app's marketing version. Before publishing, create that immutable tag
from the exact release source and verify it is publicly reachable. Never move
a released version's tag to different source.

Check the app or an app ZIP against the canonical legal files in that source
checkout, supplying the final marketing version:

```bash
python3 Scripts/verify-bundled-notices.py /absolute/release/Ode.app --version X.Y.Z
```

This checks exact notice bytes and the packaged marketing version, not source
publication, signatures or UI acceptance. It applies to Mac and mobile apps;
Chromium packaging preserves the host framework's legal resources in the app.
Review the expanded Licenses area offline on each shipping platform too.

Before publishing, or after mounting a published disk image, inspect the app
with standard macOS tools:

```bash
codesign --verify --deep --strict --verbose=2 /Volumes/Ode/Ode.app
spctl --assess --type execute --verbose=4 /Volumes/Ode/Ode.app
xcrun stapler validate /Volumes/Ode/Ode.app
```

Install the disk image on a clean macOS account and exercise both a manual
update check and the normal relaunch path.

A release also meets the moment ceilings in `Scripts/moment-budgets.json`,
checked on a real build: a review build of the release commit, run under the
test harness (`ODE_TEST_HARNESS=1` with an isolated session) through tab
switches, Command Bar opens and Returns, sleeping-tab wakes and relaunches.
`tools/dev/ode-harness.py --profile ID moments moments.json` writes that
launch's summary, per moment the count, median, 95th percentile and longest,
by engine and by whether the tab slept, with the correctness counters, and
`Scripts/check_moment_budgets.py moments.json` prints one line per gate and
exits non-zero when a 95th percentile is over its ceiling, a counter (blank
frames on a switch, tabs slept with typed text, tabs a relaunch did not
restore) is above zero, a hang of 250 ms or more was recorded, or a gated
moment was not measured. Ode times these moments in every build and keeps
them on the Mac, in `moments.json` beside the session: durations, counts and
those tags only, never an address, a title or typed text, and nothing sends
them anywhere.

## What releases Ode

`Scripts/release-ode.sh` is Ode's release; the repository holds no other
release automation.

## Prebuilt Chromium engine

Ode consumes the Chromium engine that upstream Crest publishes as GitHub
releases named `chromium-engine-<key>` on `pauljoda/Crest`
(`engine_repository` in `release-ode.sh`). The key is a hash over every
engine input, which `Scripts/control-plane/chromium_engine.py` lists: the
source lock, the host patch and overlay, the host header, the four contract
headers and the prepare, apply, configure and build scripts. An engine
exists for a checkout only while those inputs match a published release byte
for byte.

The core's content filter downloads its scriptlet resources
(`ublock-resources.json`, pinned by SHA-256 in `FilterLibrary.cs`) from the
same repository's `ublock-resources-<version>` release, and moves to Ode's own
release once Ode publishes one.

To see which release a checkout needs and whether it is published:

```bash
python3 Scripts/control-plane/chromium_engine.py tag
python3 Scripts/release-preflight.py --online > /absolute/evidence/preflight.json
```

`release-ode.sh --check` also reports when the engine is neither cached nor
downloadable.

When the key has no published release, because an engine input changed in
this repository or the upstream release is gone, either:

- build the engine from the pinned recipe as
  [Fork maintenance](../CrestEngines/Chromium/ForkMaintenance.md) describes,
  then point `ODE_CHROMIUM_APP` at the built `Chromium.app` when running
  `release-ode.sh`; or
- publish that build with
  `Scripts/control-plane/publish-chromium-engine.py --repository <owner/repo>`
  and set `engine_repository` in `release-ode.sh` to the same repository, so
  later releases download it.

The engine's own README covers its inputs and packaging; see "Releasing" in
[the Chromium engine README](../CrestEngines/Chromium/README.md).
