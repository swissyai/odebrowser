# Repository settings

Part of the repository's configuration lives in GitHub's settings rather
than in the tree. Apply the settings below by hand when the repository is
created and before it accepts contributions, then run the checks with a
throwaway fork at the end. The branch ruleset and the code owners are kept
as files, `.github/rulesets/main.json` and `.github/CODEOWNERS`, so a change
to either is reviewed like any other change. After changing the ruleset in
GitHub, export it over `.github/rulesets/main.json`.

## General

- Default branch: `main`.
- Discussions: off. Questions and feedback go to the feedback page that
  `SUPPORT.md` names.

## Branch ruleset

Import `.github/rulesets/main.json` under Settings > Rules > Rulesets > New
ruleset > Import a ruleset, and leave it active. On the default branch it:

- requires a pull request for every change, with no required approvals;
- requires the `all-checks-pass` job of `Build Ode` and the
  `AI usage declaration` and `Developer Certificate of Origin` jobs of
  `Contribution checks` to pass;
- requires a code owner's review when a pull request touches a path listed
  in `.github/CODEOWNERS`: the workflows and the actions they run, the
  dependency manifests and pins, `SECURITY.md`, and the high-risk paths
  `CONTRIBUTING.md` lists;
- blocks force pushes and deletion of the branch.

The contribution checks run in their own workflow because they rerun when a
pull request's description is edited, so the ruleset names them beside
`all-checks-pass` rather than through it.

The admin role may bypass the ruleset for pull requests only. The owner's
own pull requests, workflow changes included, merge without a second
reviewer, but a direct push to `main` is refused. Change the bypass mode to
always allow only if the owner intends to push to `main` directly. After the
import, export the ruleset and compare it with the file: the export names
the bypass actor by role ID, and if that is not `5`, commit the export in
place of the file.

The app builds in `Build Ode` run on the `xcode-27` runner label. Confirm a
job with that label schedules on this account; otherwise every change that
builds an app waits on those jobs, and `all-checks-pass` keeps it from
merging.

## Labels

The workflows apply labels but do not create them. Create these first:

- Path labels from `.github/labeler.yml`: `area: engine inputs`,
  `area: high risk`, `area: scripts`, `area: help center`, `area: tests`,
  `area: swift app` and `area: core`.
- States: `accepted`, `waiting on author`, `waiting on reporter` and
  `stale`.
- Close reasons that `.github/workflows/close-with-reason.yml` knows:
  `close: formatting or renames`, `close: engine inputs`, `close: no issue`
  and `close: no evidence`.

## Interaction and pull request limits

Under Settings > Moderation options > Interaction limits:

- Pull request limits: at most 3 open pull requests for users without write
  access, with draft pull requests counted toward the limit and users with
  at least 2 merged pull requests exempt. Leave the account-age exemption
  off. `CONTRIBUTING.md` states this limit.
- Temporary interaction limits: none at launch. If a burst of low-quality
  issues or pull requests arrives, limit interactions to prior contributors
  for 24 hours to a week.

## Actions

Under Settings > Actions > General, require approval of fork pull request
workflows for all external contributors. Each external pull request's checks
then wait for one approval, which is also the first look at it, and its
required checks stay pending until then, so it cannot merge unapproved.

## Security

Under Settings > Code security:

- Private vulnerability reporting: on. `SECURITY.md` sends reports there.
- Dependabot alerts: on. Version updates are configured in
  `.github/dependabot.yml`.

## Checks with a throwaway fork

Run these once from a second GitHub account before the repository is
announced, then delete the fork.

1. Fork the repository and open a small pull request. Note whether "Allow
   edits by maintainers" is ticked by default, and whether it reads "Allow
   edits and access to secrets by maintainers", which GitHub shows when the
   fork has workflows. The maintainer adds the version bump and release-note
   entry on the contributor's branch when merging; when the box is off by
   default, only the template's reminder keeps it on.
2. With approval required for all external contributors, note whether
   `Pull request labels` labels the pull request before its checks are
   approved or only after. If it waits, path labels appear only once the
   first run is approved.
3. Label the pull request `waiting on author`, comment from the fork
   account, and confirm the label comes off.
4. Apply `close: no evidence` and confirm the reason is posted and the pull
   request closes. Then check whether the fork account can reopen it; the
   closing comments ask the author to comment so the maintainer reopens it.
