# Ode repository instructions

These instructions apply to every coding agent working in this repository.
They hold on any machine and contain nothing private.

## Load the contribution skill first

Before changing source, tests, documentation or pull request text, load the
`ode-contribution` skill at `.agents/skills/ode-contribution/SKILL.md`
(Claude Code finds the same skill through `.claude/skills/ode-contribution`).
It carries the C# and Swift style, the architecture, UI and test rules, and
the pull request requirements. Every AI-assisted pull request must follow it,
and the pull request template asks the author to confirm that it did.

`CONTRIBUTING.md` and `Documentation/RepositoryGuardrails.md` remain the base
contract for setup, validation and change discipline. Contributions follow
`CONTRIBUTING.md`: an issue first for anything beyond a small fix, one
outcome per pull request, and a `Signed-off-by` trailer on every
contributed commit (`git commit -s`); the maintainer's own commits are
exempt from the sign-off check.

## Versioning completed work

- Every committed app-code change advances `MARKETING_VERSION` with
  `Scripts/set-version.sh --patch` unless the commit explicitly opens a new
  release line.
- Keep routine development versions on the current release line until a
  maintainer explicitly requests a release-line change; the version already in
  `main` is the source of truth.
- Do not increment `CURRENT_PROJECT_VERSION`; the release pipeline owns
  distributed build numbers.
- Before committing app-code changes, stage `Config/Version.xcconfig` with the
  task-owned files and run `Scripts/check-version.sh --fix-commit`.

## Explicit release notes

- Every committed app-code or architecture-significant change adds a new
  stable entry to `Documentation/ReleaseNotes.json` in the same commit.
- Use a unique lowercase kebab-case ID and one of `new`, `improved`, `fixed`,
  `removed`, or `internal`. Use `internal` only when the change should not
  appear in public release notes.
- A `removed` entry's message says what is gone. It also carries
  `replacement`, naming what to use instead or reading exactly
  `no replacement`, and `removedIn`, the version from which the behavior is
  gone, which is the version its own commit sets.
  `Scripts/check-version.sh` rejects a removal that lacks either, or that is
  gone from a later version than the checkout's. "Removing behavior" in
  `Documentation/Distribution.md` says when a removal may ship.
- The app reads the bundled catalog and shows no release notes at all when
  an entry's category is one `BrowserAboutReleaseNoteCategory` does not
  decode, so the first entry of such a category ships in the same change
  that teaches the app to decode it.
- Write public entry messages as concise user-facing outcomes rather than
  commit subjects, implementation details, issue IDs, or test descriptions.
- Never reuse, reorder, or delete an existing entry ID; append new entries at
  the end. Stage the catalog with the task-owned files before running
  `Scripts/check-version.sh --fix-commit`.

## Version and release notes in contributed pull requests

- A pull request from a fork or from anyone other than the repository owner
  carries no version bump and no release-note entry; the maintainer adds both
  when merging, and `Scripts/check-version.sh --fix-commit` requires them only
  on `main` and in the owner's own commits.

## Generated localization catalog

- Whenever `OdeShared/Resources/Localizable.xcstrings` changes, treat the
  regenerated catalog as task-owned output and include it with the current
  work instead of leaving it as unrelated worktree noise.

## Published Chromium engine

- The release script cannot build Chromium; it downloads a prebuilt engine
  named by the key `Scripts/control-plane/chromium_engine.py` computes over
  its inputs: `CrestEngines/Chromium/source.lock.json`, `host-inputs.json`,
  `Patches/`, `Overlay/`, `Apple/CrestChromiumHost.h`, and the prepare, apply,
  configure, and build scripts in `Scripts/control-plane/`.
- Any change to those inputs needs a new engine published by a maintainer, as
  described under "Releasing" in `CrestEngines/Chromium/README.md`. A branch
  whose key has no published `chromium-engine-<key>` release fails its next
  release. State in the pull request that the change touches engine inputs so
  the publish is planned with the merge.
- Swift, native core, and packaging changes reuse the published engine and
  need no new one.
- The core links a prebuilt content filter the same way:
  `CrestCore/native/ContentFilter/artifact.lock.json` names it and
  `Scripts/control-plane/fetch-content-filter.py` downloads its
  `content-filter-<key>` release. The crate and
  `Scripts/control-plane/content_filter.py` keep their paths and bytes; a
  change to either has no published archive, so the build compiles the crate,
  which needs Rust. Say so in the pull request too.

## Test retention and cleanup

- Never create, commit, or upload task-specific validation or results
  Markdown, security findings or audit reports, benchmark logs, screenshots,
  or closeout packets in this repository, including `Documentation/`. Put
  concise evidence in the pull request; keep necessary local artifacts outside
  the checkout.
- Documentation is for maintained product behavior and contributor
  instructions, not dated test totals, machine paths, investigation
  transcripts, or cleanup narratives. `ReleaseNotes.json` and the generated
  roadmap remain supported public records.
- Keep the permanent suite focused on important, durable contracts: shared
  browsing and state behavior, persistence and migration, privacy and
  authorization boundaries, extension compatibility and recovery, and measured
  performance limits.
- Visual appearance, layout, animation, styling, and static UI copy are
  covered by manual product review. Do not add or retain permanent tests
  solely for those details. Retain UI-driven tests when their assertions
  protect browsing state, Space or window ownership, privacy, native input
  routing, accessibility semantics, or another durable behavioral contract.
- Temporary tests, probes, fixtures, and diagnostic harnesses may be used
  while reproducing an issue, developing a fix, or validating an experiment.
  Before handing off completed work, remove those temporary artifacts and any
  obsolete or redundant tests made unnecessary by the final implementation.
- Retain a regression test from a bug fix only when it protects an important
  behavior that is not adequately covered elsewhere. Its origin in a bug fix,
  age, or filename alone is not a reason to keep or delete it.
- Prefer one focused behavioral test at the owning layer over duplicated
  platform cases, source-text assertions, file-layout checks, trivial wrapper
  tests, or tests that mirror implementation details. Preserve separate
  platform coverage when adapters have distinct behavior.
- Before removing a permanent test, identify the contract it covered and the
  stronger retained coverage, or explain why that contract is obsolete. Do not
  delete a failing test merely to obtain a green run; resolve whether the
  product contract or the expectation changed.
- During cleanup, consolidate overlapping fixtures and cases rather than
  adding a new test framework. Run the affected retained tests and report what
  was removed, what protection remains, and any remaining validation gaps.

## Shell builds, tests and cleanup

- `Scripts/control-plane/install-dotnet.sh` installs the .NET SDK pinned by
  `OdeCore/global.json` in `~/.dotnet` and leaves `PATH` alone, so a new
  shell has no `dotnet`. The scripts that run it, `lint-dotnet.sh`,
  `generate-contracts.sh`, `build-experiment.sh` and
  `build-ios-experiment.sh`, add `~/.dotnet` themselves when no `dotnet` is
  on `PATH` (`Scripts/control-plane/dotnet-path.sh`). Before running
  `dotnet` yourself, run `export PATH="$HOME/.dotnet:$PATH"` or
  `source Scripts/dev-env.sh`. Run `Scripts/dev-env.sh` on its own to print
  the toolchain it finds and the commands below with this checkout's paths
  filled in.
- Run the Swift tests without opening Xcode in two steps: build once with
  `xcodebuild build-for-testing -project Ode.xcodeproj -scheme Ode
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/DerivedData"
  CODE_SIGNING_ALLOWED=NO`, then run `xcodebuild test-without-building` with
  the same arguments. Repeat only the second step until source or test code
  changes.
- Tests build only the Debug configuration, so they never compile the
  Release side of `#if DEBUG || ODE_REVIEW_BUILD` code, such as the test
  harness's release stubs. After changing a signature that such code calls,
  also run `xcodebuild build -project Ode.xcodeproj -scheme Ode
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  -IDEBuildingContinueBuildingAfterErrors=YES`.
- Narrow a run while you work, then run the whole suites before committing.
  One Swift class or test: `-only-testing:OdeTests/<TestClass>` or
  `-only-testing:OdeTests/<TestClass>/<testMethod>` on `test-without-building`.
  One core class: `(cd OdeCore && dotnet test tests/OdeCore.Tests --filter
  "FullyQualifiedName~<TestClass>")`. One script test file:
  `python3 -m unittest discover -s Scripts/Tests -p 'test_<name>.py'`.
- `Scripts/check-complexity.sh --base main` measures the Swift, C# and
  Python functions in the files changed against `main` with lizard and
  lists every one whose cyclomatic complexity passes 15 or that spans more
  than 80 lines. It fails only on new ones: the functions
  `Scripts/complexity-baseline.json` records are existing debt, listed and
  allowed while they grow no further. Split a new one rather than recording
  it. When a change moves or renames recorded debt, rewrite the baseline
  with `Scripts/check-complexity.sh --write-baseline` in the same commit and
  check that its diff only moves or removes entries. The check runs lizard
  through `uvx` and passes with a note when uv is missing
  (`brew install uv`).
- `xcodebuild` stops compiling after the first failure, so a broken build
  reports one error per run. To see every error in one build, add
  `-IDEBuildingContinueBuildingAfterErrors=YES` and filter the output with
  `rg ' error: ' | sort -u`.
- Xcode registers every app it builds with LaunchServices, including the test
  host `DerivedData/Build/Products/Debug/Ode.app` that `build-for-testing`
  leaves behind, and the registration outlives the folder. Before deleting a
  Derived Data folder or a built copy, unregister each app in it with
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <path>`,
  then delete it by its literal absolute path. `Scripts/dev-env.sh
  --registered` lists the copies macOS still has registered.
  `build-experiment.sh`, `Scripts/validate.sh` and `Scripts/audit-periphery.sh`
  unregister the apps in the temporary Derived Data they delete
  (`Scripts/control-plane/unregister-apps.sh`); the copy `build-experiment.sh`
  writes to the path you give it stays registered until you unregister it.
- Several checkouts can build on one Mac at the same time. Keep Derived Data
  inside the checkout (`DerivedData/` is ignored), give logs and result
  bundles written outside it a prefix unique to the branch, such as
  `<branch>-build.log`, and wait on your own process or log rather than on
  `pgrep -f xcodebuild`, which also matches other checkouts' builds.
- The repository scripts use zsh, the macOS default shell, which fails a
  command whose unquoted glob matches no file. Quote patterns passed as
  arguments, such as `grep -rn --include='*.swift'`, or use
  `rg -g '*.swift'`.
