---
name: ode-contribution
description: Required before any AI-assisted change to Ode. Loads the project's C# and Swift style, the core-owns-state and engine-adapter architecture rules, the single-window and design-system UI rules, the test policy, and the pull request, verification and writing requirements. Use whenever an AI tool writes, refactors, reviews or describes Ode source, tests, documentation or pull request text.
---

# Contributing to Ode with an AI agent

Every pull request that an AI tool helped produce must follow this skill, and
the pull request template asks the author to confirm that it did. Read it in
full before changing anything, then keep it loaded while you work. It adds the
rules that are not obvious from the code; `CONTRIBUTING.md`,
`Documentation/RepositoryGuardrails.md` and `Documentation/ARCHITECTURE.md`
remain the base contract.

## Before you start

1. Read `CONTRIBUTING.md` and `AGENTS.md` at the repository root.
2. Run `Scripts/bootstrap.sh` once per clone. It generates the Xcode project
   and verifies this skill is linked for Claude Code.
3. Work from the issue, or from the maintainer's description of a small fix;
   `CONTRIBUTING.md` asks for an issue first for anything beyond that. Keep
   the pull request to that one outcome.

## Code style

The full style guide for C# and Swift is in
[`references/library-style.md`](references/library-style.md). Apply it to every
type you touch. The rules that matter most:

- **Section layout.** Members of every type follow the same order in both
  languages: Static Variables, Variables, Initializers (Constructors),
  Abstract Methods, Actions grouped by purpose, Mutators. C# uses
  `#region`, Swift uses `// MARK: -`. Large purposes move to
  `Type.Purpose.cs` or `Type+Purpose.swift`.
- **Objects describe themselves.** A type owns its data and every behavior that
  depends on it. No sibling `*Codes`, `*Policy`, `*Rules`, `*Helper` or
  `*Utilities` types, and no extension files that switch over its kinds.
- **Behavior gets a file, plain data does not.** A type with behavior is the
  primary type of its own file. Data-only records, structs and case-only enums
  live in a `Types` region at the top of their one owner's file, or in one
  shared concept file when many consumers share them.
- **Self-describing fixed sets.** Modes, reasons, states, statuses, roles and
  capabilities are one type whose static instances define the members, each
  constructed with the values that make its behavior emerge. Methods never
  switch on a particular member.
- **Typed values, never raw codes.** Decode a wire string once at the boundary
  and dispatch on the typed value. No `status == "supported"`,
  `execute("tab.open")` or string-matched errors. Wire and persisted payloads
  are typed `Codable` or record models, not dictionaries.
- **Messages implement their own behavior.** Intents, queries and events are
  dispatched by polymorphism: each case overrides the method its family
  declares. No type switches, handler interfaces or generated dispatch.
- **Touch-only.** Apply the layout to the files your change touches. A feature
  pull request never carries a repository-wide reformatting pass.
- **Formatters and builds.** Before finishing, run
  `Scripts/check-swift-format.sh` for Swift changes,
  `Scripts/control-plane/lint-dotnet.sh` for OdeCore changes, and build the
  affected targets.

## Architecture

- **The core owns shared state.** Spaces, tabs, folders, splits, windows,
  history and behavior preferences live in OdeCore. Swift renders that state
  and sends intents. Never mutate `BrowserStore.session` or any other shared
  state directly from Swift; add or use a core intent and apply the change it
  returns. Only appearance preferences, window geometry and transient
  presentation stay in Swift.
- **Everything is a named object.** Intents, changes, engine commands and
  events are named record types. There are no operation strings and no code
  tables; the generator owns the wire tags. Rule failures are objects such as
  `TabLimitReached(limit)`, never string codes. Identifiers are plain
  `Guid`/`UUID` used at boundaries, with no one-field wrapper types; a wrapper
  exists only for an invariant or behavior, such as `SiteOrigin`. Make the
  difference between a core intent and a direct engine call visible at the call
  site.
- **Engines stay behind adapters.** Shared code never calls WebKit or Chromium
  APIs; it talks to the engine abstraction. A page opened by another page runs
  in the opener's engine. Per-site and default engine rules apply only to
  navigations a person starts.

## Windows and UI

- **Ode is a single-window app.** Never create a window the person did not
  ask for. Page and extension popups open as a Quick Window in the opener's
  engine and Space, where the person keeps or drops them. DevTools docks
  inside the window. An unexpected window during validation is a defect, not a
  detail.
- **Reuse the design system.** Interactive rows and tiles use
  `odeInteractiveSurface`; small glyph buttons use `OdeChromeButtonStyle`;
  colours come from the Ode tokens and the template house palettes. No
  ad-hoc opacity fills, no system rainbow colours, no bespoke buttons or
  cards. Every interactive control has hover and pressed states from the
  system. Search `OdeShared/DesignSystem` before writing any new fill or
  control.
- **Every menu item has an icon.** Each item of a menu, context menu or
  submenu Ode builds shows an icon: an SF Symbol for an action, and the
  Space's icon for a Space (`BrowserSpaceIdentityLabel`), as Move to Space
  does. Apply `odeMenuActionLabelStyle()` inside each `Menu` and
  `contextMenu` builder, submenus included; applied to the control that opens
  the menu, it does not reach the rows.
- **Every popover uses `odePopover`.** Present popovers with
  `odePopover(isPresented:)` or `odePopover(item:)`, never SwiftUI's
  `popover`. A popover inherits the Space's ink or a forced scheme from the
  view it comes from, while macOS draws its glass from the page behind it;
  `odePopover` draws the content on Ode's solid flyout surface, in that
  surface's own appearance, and keeps it open while the Colors panel is in use.
- **No modal notices.** Informational feedback such as "copied" or "captured"
  goes through the top-of-window notice capsule
  (`BrowserChromeState.showNotice`). Alerts and sheets appear only when the
  person must decide something.

## Tests

- **Default to no new test.** Add a permanent test only for a contract that
  breaks silently: extension compatibility and recovery, persistence and
  migration, Space and window ownership, privacy and authorization boundaries,
  the sync codec, Keychain access, native input routing, and security
  decisions such as download risk or update trust.
- **Never test appearance.** No tests for layout numbers, copy, SF Symbol
  names, animation, settings-pane structure, previews, file layout, or
  source-text greps. Review those in the running app.
- **One test at the owning layer.** Do not duplicate a shared contract across
  platform test targets unless the adapters genuinely diverge, and do not add
  trivial wrapper tests.
- **Remove probes; never delete to go green.** Temporary probes, fixtures and
  harnesses used while reproducing a problem come out before the pull request.
  A failing test is resolved by deciding whether the contract or the
  expectation changed, never by deleting it.

## Pull request

- **Version and release note.** A pull request from a fork or from anyone
  other than the repository owner carries neither; the maintainer adds the
  patch bump and the release-note entry when merging. On `main` and in the
  owner's own commits, every commit that changes app code runs
  `Scripts/set-version.sh --patch`, appends a new entry with a unique
  lowercase kebab-case ID to `Documentation/ReleaseNotes.json`, stages
  `Config/Version.xcconfig` with the change, and passes
  `Scripts/check-version.sh --fix-commit`. Never change
  `CURRENT_PROJECT_VERSION`.
- **One focused pull request.** No scope widening and no drive-by refactors.
  When a change regenerates `OdeShared/Resources/Localizable.xcstrings`,
  the regenerated catalog is part of that change. Edit `project.yml` and run
  `xcodegen generate`; never hand-edit the Xcode project.
- **Engine inputs need a maintainer.** Changes under
  `CrestEngines/Chromium` (patches, overlay, the host header, the
  control-plane prepare, apply, configure and build scripts) require a
  prebuilt engine that only maintainers can publish. Say so in the pull
  request description so the publish is planned with the merge. The same goes
  for the content filter crate in `CrestCore/native/ContentFilter`, whose
  prebuilt library a maintainer publishes.
- **Declare AI use.** Tick both boxes in the pull request template's AI usage
  section. A continuous-integration check reads them.
- **Sign off every contributed commit.** Commit with `git commit -s`, so
  each commit carries the `Signed-off-by` trailer `CONTRIBUTING.md`
  describes; the continuous-integration check rejects unsigned commits from
  contributors and exempts the maintainer's own.

## Showing a change works

`CONTRIBUTING.md` sets out the five evidence levels, from a packaged build
updated from a local feed down to unit tests only. Apply them like this.

- **Write the cases before you change code.** The reported case under the
  reporter's conditions; every surface that reaches the behavior: the Mac
  app, both engines when the change crosses the engine adapter, and the
  iPhone app when shared code changes; and one nearby case that must not
  change. Do not edit the cases afterwards to fit the result.
- **Reproduce on the unchanged code first.** Run one procedure on a build
  without your change and record the failure, then run the same procedure
  on the change. Before trusting either result, confirm which build ran,
  from the build number in Settings > About or a log line.
- **Use the strongest level the change allows,** and name it in the first
  sentence of your report. Updates, packaging, signing and entitlements
  need level 1 on a separate macOS account, never the person's installed
  Ode.
- **Account for the whole diff.** Explain every test assertion you added,
  changed or removed.
- **Report in one shape.** One sentence with the claim and its level; each
  case with its before and after; then "Not proved:" with the reason for
  each gap, including how real the environment was. The report goes in the
  pull request, never in the tree.
- **This is not evidence on its own:** "it builds"; "tests pass" for a
  change people see or a page or engine bug; a screenshot that does not
  show the state the claim is about; a run of an app started before the
  change was built; a WebKit-only run for a change on the Chromium path; a
  Simulator run for a Mac-only change; a run in the installed Ode instead of
  an isolated session.

## Verification and reporting

- **Report exactly what ran.** Run the relevant gates before saying a change
  is done, and state in the pull request which tests and builds ran and their
  results. Never describe untested work as verified.
- **Verify UI in the running app.** Visual and layout changes are checked in
  the real app, Simulator or browser, never only by tests. Launch fixtures and
  validation sessions with `ODE_ISOLATED_SESSION=1` so they never touch
  real browsing data.
- **Remove test copies when you finish.** Debug, test and harness builds run
  as `com.odebrowser.ode.dev`, apart from the person's own Ode, but every
  copy still registers with macOS as a browser, and a Release build or a
  product package takes the released identifier itself, so macOS can hand
  links, passkey requests and later test launches to the wrong copy. Before
  handing off, quit those copies, unregister each with
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <path>`,
  then delete it. Unregister first, because an app moved to the Trash
  registers again at its Trash path. Never remove or replace the person's
  installed Ode.
- **Show visual changes in the pull request.** A pull request that changes
  what people see includes screenshots of each change in its description, so
  a reviewer can check it without building. Add a short recording where the
  change moves, before-and-after pairs where the difference is subtle, and
  both appearances where light and dark differ. Take them in the running app
  or Simulator, attach them to the pull request, and never commit them.
- **Regressions: read history, restore once.** When a second regression
  appears in the same area after a refactor, stop guessing. Read the commits
  that built the working behavior, compare the current behavior against the
  last known good revision, and restore every gap in one pass.
- **No artifacts in the repository.** Task reports, audit write-ups,
  screenshots, benchmark logs and closeout packets never enter the tree,
  including `Documentation/`. Evidence belongs in the pull request text.

## Building and testing from a shell

`Scripts/dev-env.sh` prints these commands with the checkout's own paths;
`AGENTS.md` carries the same steps.

- **Put .NET on the path before running it yourself.** The pinned SDK lives
  in `~/.dotnet`, and its installer never touches `PATH`. `lint-dotnet.sh`,
  `generate-contracts.sh`, `build-experiment.sh` and
  `build-ios-experiment.sh` find it there on their own; start a shell that
  runs `dotnet` directly with `source Scripts/dev-env.sh` or
  `export PATH="$HOME/.dotnet:$PATH"`.
- **Test Swift without Xcode.** `xcodebuild build-for-testing` once, then
  `xcodebuild test-without-building` with the same `-project Ode.xcodeproj
  -scheme Ode -destination 'platform=macOS,arch=arm64' -derivedDataPath
  "$PWD/DerivedData" CODE_SIGNING_ALLOWED=NO`. Rebuild only when source or
  tests change.
- **Narrow, then widen.** Iterate on one class: `-only-testing:OdeTests/<TestClass>`
  for Swift, `dotnet test tests/OdeCore.Tests --filter
  "FullyQualifiedName~<TestClass>"` for the core,
  `python3 -m unittest discover -s Scripts/Tests -p 'test_<name>.py'` for the
  scripts. Run the full suites before you commit.
- **See every compile error at once.** A failing `xcodebuild` stops after its
  first error. Add `-IDEBuildingContinueBuildingAfterErrors=YES` and pipe the
  output through `rg ' error: ' | sort -u`, then fix the whole list before the
  next build.
- **Unregister the test host too.** `build-for-testing` leaves
  `DerivedData/Build/Products/Debug/Ode.app`, and LaunchServices keeps it
  registered after the folder is gone. Run `lsregister -u` on every built app,
  then delete Derived Data by its literal path; `Scripts/dev-env.sh
  --registered` shows what is still registered. `build-experiment.sh` cleans
  up its own temporary Derived Data, but the copy it writes to your path is
  yours to unregister and delete.
- **Own your build files.** Other checkouts may be building on the same Mac.
  Keep Derived Data in the checkout's ignored `DerivedData/`, prefix logs and
  result bundles with the branch name, and wait on your own process, never
  `pgrep -f xcodebuild`.
- **Quote globs.** The scripts run in zsh, where an unquoted pattern that
  matches nothing fails the command: write `--include='*.swift'` or
  `rg -g '*.swift'`.

## Writing

- **Release notes are user outcomes.** An entry says what changed for the
  person using Ode, never a commit subject, implementation detail, issue ID
  or test description.
- **Interface copy.** Read and apply the canonical
  [interface-writing rules](../../../Documentation/InterfaceWriting.md) before
  changing user-facing text. They govern concise default views, necessary
  consequences, contextual help, recovery and native anti-slop review.
- **Plain pull request descriptions.** What changed, why, what was validated,
  screenshots of any visual change, and the AI declaration. No filler, no
  generated-sounding prose, no emoji headings.
- **Documentation describes lasting behavior.** Maintained product behavior
  and contributor instructions only; never dated totals, machine paths,
  investigation transcripts or cleanup narratives.

## Checklist before opening the pull request

- [ ] Touched types follow the section layout and typed-value rules.
- [ ] Formatter, linter and affected builds ran clean.
- [ ] Shared state changes go through core intents; no direct engine calls in shared code.
- [ ] No new windows, ad-hoc fills or modal notices; every menu item has an icon.
- [ ] Tests only for silent-breaking contracts; probes removed.
- [ ] Owner's commits only: patch bump, release-note entry and `check-version.sh --fix-commit` pass.
- [ ] Pull request lists what ran, and both AI usage boxes are ticked.
- [ ] "How verified" names the evidence level, the failure before the change, the same steps after it, one nearby case that must not change, and what was not proved.
- [ ] Every contributed commit carries a `Signed-off-by` trailer.
- [ ] Interface copy follows `Documentation/InterfaceWriting.md`; screenshots show default and relevant help/error states.
- [ ] Visual changes are shown in screenshots attached to the pull request.
- [ ] Test copies of Ode are quit, unregistered and deleted.
- [ ] Derived Data apps, the test host included, are unregistered before the folder is deleted.
