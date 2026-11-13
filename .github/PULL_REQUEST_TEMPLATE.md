<!-- A contributor can have at most 3 pull requests open at a time, drafts included. See "Open pull request limit" in CONTRIBUTING.md. -->

Closes #

<!-- The issue this pull request answers. Required for anything beyond a small fix, as CONTRIBUTING.md defines it; a small fix without an issue can drop this line. -->

## What changed

<!-- The one outcome, as someone using Ode would notice it. Say so if it changes the prebuilt engine's inputs. -->

## How verified

<!-- See "Showing a change works" in CONTRIBUTING.md. Name the strongest level you reached: 1 packaged build updated from a local feed, 2 review build driven through the real UI, 3 Debug build used by hand, 4 integration tests, 5 unit tests only. Name the commands you ran. Tests support the evidence; for a change people see, they are not the evidence. -->

Level:

- Failure on the unchanged code:
- Same steps on this change:
- Nearby case that must not change:
- How real the environment was, and what this does not prove:

## AI usage

<!-- Leave both boxes empty when no AI tool touched this change. -->

- [ ] AI tools helped produce this change.
- [ ] I ran the `ode-contribution` skill (`.agents/skills/ode-contribution/SKILL.md`), followed it, and reviewed every generated line.

<!-- Sign off every commit with `git commit -s` (see "Developer Certificate of Origin" in CONTRIBUTING.md), and keep "Allow edits by maintainers" ticked so the maintainer can add the version bump and release note when merging. -->
