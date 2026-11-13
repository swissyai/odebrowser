# Contributing

Contributions are welcome. Open an issue first for anything beyond a small
fix, so the change is agreed before the work starts; a small fix can go
straight to a pull request. Every commit is signed off (see "Developer
Certificate of Origin" below).

## Requirements

- An Apple silicon Mac with macOS 26.1 or later.
- Xcode with the macOS and iOS 26.1 SDKs or later (`project.yml` sets
  the deployment targets).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Scripts/bootstrap.sh`
  generates `Ode.xcodeproj` with it.
- The .NET SDK pinned by `OdeCore/global.json`;
  `Scripts/control-plane/install-dotnet.sh` installs it under `~/.dotnet`.
- [ripgrep](https://github.com/BurntSushi/ripgrep), used by
  `Scripts/validate-identity.sh` and the script tests.
- Python 3.11 or newer for `Scripts/` and `tools/dev/`.
- [uv](https://docs.astral.sh/uv/), whose `uvx` runs lizard for
  `Scripts/check-complexity.sh`.
- Node 24 to build the Help Center in `HelpCenter/`.
- For releases only: Sparkle's `generate_appcast` and `sign_update`
  (resolved with the Sparkle package into DerivedData, or `ODE_SPARKLE_BIN`)
  and the GitHub CLI, which `Scripts/release-ode.sh` uses to download the
  prebuilt engine. See [Distribution](Documentation/Distribution.md).

## Working in the repository

- Run `Scripts/bootstrap.sh` once per clone. It generates the project and
  runs the version and identity checks.
- Keep each commit to one change, with a subject of the form
  `area: what changed`.
- Run `Scripts/validate-identity.sh`,
  `python3 -m unittest discover -s Scripts/Tests` and
  `(cd OdeCore && dotnet test tests/OdeCore.Tests)` before committing; the
  README lists the harness scripts for the app itself.
- Run `Scripts/check-complexity.sh --base main` before committing. It fails
  when a function you changed or added passes a cyclomatic complexity of 15
  or a length of 80 lines and `Scripts/complexity-baseline.json` does not
  record it as existing debt; split the function rather than recording it.
  Without uv it passes with a note.
- Run `swift tools/dev/format-xcstrings.swift` after scripted catalog edits,
  `tools/dev/normalize-pbxproj.py` after `xcodegen generate`, and
  `Scripts/control-plane/generate-contracts.sh` after core contract changes,
  in the same commit. Never hand-edit `Ode.xcodeproj`.
- Contributors leave `Config/Version.xcconfig` and
  `Documentation/ReleaseNotes.json` alone: the maintainer adds the patch bump
  and the release-note entry when merging, and
  `Scripts/check-version.sh --fix-commit` asks for them only on `main` and in
  the owner's own commits, as `AGENTS.md` describes.
- User-facing copy follows [Interface writing](Documentation/InterfaceWriting.md),
  including review of default, help and recovery states in the native interface.
- A change an AI tool helped produce follows the `ode-contribution` skill at
  `.agents/skills/ode-contribution/SKILL.md`.

## Pull requests

- One outcome per pull request: the issue it answers or the one fix it
  makes, with no scope widening and no drive-by refactors.
- Fill in the template: the linked issue, what changed, how you verified it
  (see "Showing a change works") and the AI usage declaration. A change to
  what people see includes screenshots.
- Changes to the prebuilt Chromium engine's inputs (`CrestEngines/Chromium`,
  `CrestContracts/include` and the control-plane engine scripts) need a
  maintainer to publish a new engine; say so in the description.
- The `Contribution checks` workflow verifies the AI usage declaration and
  the sign-off on every commit; `Build Ode` runs the tests and builds.

## Showing a change works

A pull request shows that its change works, under "How verified" in the
template. Name the strongest level you reached on this scale, strongest
first:

1. **Packaged and updated.** A signed package from `Scripts/release-ode.sh`,
   installed on a separate macOS account and updated from a local feed with
   `Scripts/serve-updates-locally.sh` ("Testing an update on this Mac" in
   [Distribution](Documentation/Distribution.md)). Changes to updates,
   packaging, signing and entitlements need this level; when you cannot sign
   a package, the maintainer runs it before release.
2. **Review build through the real UI.** `OdeNativeCore` or a Chromium review
   package, driven under the test harness (`ODE_TEST_HARNESS=1` with an
   isolated session) with `tools/dev/ode-harness.py`. A change to tab
   switching, the Command Bar, sleeping tabs or relaunch also runs
   `Scripts/check_moment_budgets.py` before and after.
3. **Debug build by hand.** The change used in a Debug build launched with
   `ODE_ISOLATED_SESSION=1`, with screenshots or a recording.
4. **Integration tests.** Tests through a public interface: the core's
   contract tests, the native ABI tests, or script tests that run the
   script.
5. **Unit tests only.**

Whatever the level, the evidence covers four things:

- **The failure on the unchanged code.** Run the steps on `main` without
  your change and show what goes wrong; for a feature, show that the steps
  do not work yet.
- **The same steps on the change.** Rerun exactly those steps with your
  change and show the result.
- **One nearby case that must not change.** Pick a case your change could
  plausibly break, such as the other engine, another Space or the path next
  to the one you fixed, and show it behaves as before.
- **How real the environment was, and what was not proved.** Name the
  build, the engine and whether the session was isolated, and list what you
  did not test and why.

Tests and type checks support the evidence; for a change people see, they
are not the evidence. None of these is evidence on its own:

- "It builds."
- "The tests pass", for a change to what people see or to page or engine
  behavior.
- A screenshot that does not show the state the claim is about.
- A run of an app that was started before the change was built.
- A WebKit-only run for a change on the Chromium path.
- A Simulator run for a Mac-only change.
- A run in the installed Ode instead of an isolated session.

Evidence lives in the pull request description. Screenshots, recordings and
logs are attached there and never committed.

## High-risk paths

A person reads every change to these paths in full, on every pull request,
whoever opened it and however it was produced. Elsewhere, a review may rest
on the evidence the pull request shows. A pull request that touches one of
them gets the `area: high risk` label, and the branch ruleset requires the
code owner's review; `.github/CODEOWNERS` and `.github/labeler.yml` carry
the same list.

- **Updates and the update feed:** `OdeMac/Features/SoftwareUpdates/Models/`,
  `OdeMac/Features/SoftwareUpdates/Services/`, `Scripts/release-ode.sh`,
  `Scripts/next-release-build-number.py`,
  `Scripts/control-plane/update-feed.py` and
  `Scripts/control-plane/mark-security-update.py`.
- **Keychain and credentials:** `OdeShared/Application/Credentials/`,
  `OdeShared/Domain/BrowserCredential/`,
  `OdeShared/Infrastructure/Credentials/`,
  `OdeShared/Infrastructure/WebKit/Credentials/`, the
  `Infrastructure/BrowserPasskeyAccess/` folders of `OdeMac` and
  `OdeMobile`, and `OdeCore/src/OdeCore/Application/Credentials/` and
  `OdeCore/src/OdeCore/Contracts/Credentials/` in the core.
- **Session storage:** `OdeCore/src/OdeCore/Application/Storage/` and the
  `StoredSessionCodec` files in `OdeCore/src/OdeCore/Application/Session/`.
- **Agent gates and grants:** `BrowserAgentApprovals.swift`,
  `BrowserAgentFillRefusal.swift`, `BrowserAgentOriginGate.swift` and
  `BrowserAgentOriginGrants.swift` in `OdeMac/App/Agents/`,
  `OdeShared/Infrastructure/Downloads/DownloadPrompts.swift`, and the core's
  `OdeCore/src/OdeCore/Application/Device/Intents/Agents/` and
  `OdeCore/src/OdeCore/Application/Device/Queries/AgentReach.cs`.
- **Entitlements and Info.plists:** every `*.entitlements` and `*Info.plist`
  file.
- **Engine inputs:** the files `INPUTS` lists in
  `Scripts/control-plane/chromium_engine.py`.

## Issue first

Open or find an issue before writing code, and link it from the pull
request with a line such as `Closes #123` or `Related: #123`. A feature or a
change in behavior waits until the maintainer labels the issue `accepted`.
The one exception is a small fix: at most 50 changed lines in at most 3
files, none of them an engine input (see "Closed without review"). A small
fix may go straight to a pull request without an issue.

## Open pull request limit

A contributor can have at most 3 pull requests open at a time, drafts
included; a fourth cannot be opened until one of them is merged or closed.
The limit no longer applies once two of your pull requests have been merged.

## Closed without review

The maintainer closes these pull requests without reviewing the code. The
reason is how the change arrived, not its quality. Each reason has a label,
and its written reason is posted when the pull request is closed.

- **Drive-by formatting or mass renames** (`close: formatting or renames`).
  Reformatting code a change does not otherwise need, or renaming across
  the tree, conflicts with every open branch and buries the real change in
  review. The maintainer makes such passes as one planned change.
- **Engine inputs without a linked issue** (`close: engine inputs`). The
  files `INPUTS` lists in `Scripts/control-plane/chromium_engine.py` are
  compiled into the prebuilt Chromium engine. A change to any of them needs
  the maintainer to build and publish a new engine, so it is planned in an
  accepted issue first.
- **No linked issue beyond a small fix** (`close: no issue`). Anything larger
  than a small fix is agreed in an issue before the work starts (see "Issue
  first").
- **No evidence of verification** (`close: no evidence`). The "How verified"
  section names no level from "Showing a change works", or shows no
  before-and-after on the same steps. A description that only says the
  change works gives the review nothing to check.

## How closes happen

Every close follows a label the maintainer applies, and every closing
comment says how to come back.

- A `close:` label from the list above posts its written reason, says what
  to add or open, and closes the pull request. Comment once that is done and
  it is reopened.
- An issue labelled `waiting on reporter` gets one reminder after 21 days
  without activity and is closed 7 days later; a pull request labelled
  `waiting on author` gets one after 30 days and is closed 14 days later.
  Draft pull requests are left alone. The label comes off when the author
  comments in the conversation or pushes a commit, and any activity
  restarts the count, so an item waiting on the maintainer is never
  reminded or closed.
- Nothing else is closed for being quiet.

## Response time

Ode has one maintainer. Every new issue and pull request gets a first
response, a label or a comment, within a week. That response is not a
review date: there is no promised date for a review or a merge.

## Developer Certificate of Origin

Every contributed commit carries a `Signed-off-by: Name <email>` trailer,
which `git commit -s` adds from your Git identity; the maintainer's own
commits are exempt from the check. The trailer states that you
wrote the change, or have the right to submit it, under the licence of the
file you changed, as the [Developer Certificate of Origin](https://developercertificate.org)
sets out. The `Contribution checks` workflow rejects a pull request with an
unsigned commit; merge commits are exempt, as are pull requests opened by
bots and by the repository owner.

## Relationship to Crest

Ode started from Crest's codebase, released under the Mozilla Public License
2.0, and now develops independently; it does not merge upstream. Individual
upstream fixes may be cherry-picked when relevant. After a cherry-pick, run
`tools/dev/rename-product-strings.py`, `tools/dev/rename-identifiers.py`,
`Scripts/control-plane/generate-contracts.sh`, `xcodegen generate`,
`tools/dev/normalize-pbxproj.py` and `Scripts/validate-identity.sh`, and
commit their output with the cherry-pick.

The `Crest` prefix that remains on some type, module, folder and target
names is historical and will be renamed in a planned pass; the names the
prebuilt Chromium engine binds change when the engine is rebuilt. New code
uses `Ode` names.

## Licence

Files carry no licence header; [LICENSE](LICENSE) and [NOTICE](NOTICE) apply
to the whole tree.
