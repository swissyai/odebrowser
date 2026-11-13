# Ode documentation

The product site and [Ode Help](https://odebrowser.com/guides/) explain how
to use the browser. This directory describes the source, product behavior, and
build and release requirements for contributors.

Ode ships Chromium and WebKit together on Mac, backed by the shared native
core. iPhone and iPad keep WebKit. Start with the [engine and migration guide](../HelpCenter/docs/browsing/engines.md)
for user-visible behavior, or the architecture references below for ownership
and implementation details.

## Start here

- [Architecture](ARCHITECTURE.md) covers Space isolation, persistence,
  credentials, synchronization, and the engine boundary.
- [Repository guardrails](RepositoryGuardrails.md) describes source layout,
  validation, dependencies, and public-source checks.
- [Repository settings](RepositorySettings.md) lists the GitHub settings
  applied by hand: the branch ruleset, labels, limits and security reporting.
- [Distribution](Distribution.md) covers the release script, signing,
  notarization, the appcast, and release verification.

## Browser behavior

- [Answers](Answers.md)
- [Content blocking](Architecture/ContentBlocking.md)
- [Desktop Picture in Picture](Architecture/DesktopPictureInPicture.md)
- [Link opening](LinkOpeningPolicy.md)
- [Native tab content](NativeTabs.md)
- [Core architecture](Architecture/CoreArchitecture.md)
- [Portable control plane](Architecture/ControlPlane.md)
- [Engine abstraction](Architecture/EngineAbstractionCompletion.md)
- [Chromium engine](../CrestEngines/Chromium/README.md)

## Project participation

See [Support](../SUPPORT.md) for help guides, GitHub bug and feature forms,
and private feedback options.
[Not planned](NotPlanned.md) lists the requests Ode has decided against.
See [CONTRIBUTING.md](../CONTRIBUTING.md) for local development and the
[`ode-contribution` skill](../.agents/skills/ode-contribution/SKILL.md)
for the rules every AI-assisted change must follow.
