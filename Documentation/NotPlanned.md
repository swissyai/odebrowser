# Not planned

Requests Ode has decided against, each with the reason and what to do
instead. Every answer here restates a decision already recorded in this
repository, and the page changes only when that decision does. A request
that is not listed is still open: ask on the feedback page that
[SUPPORT.md](../SUPPORT.md) names.

## "Put Ode in the Mac App Store"

**Reason.** Ode is one Mac app, distributed directly: signed with Developer
ID, notarized by Apple, delivered as a disk image and updated through
Sparkle. Keeping one macOS product avoids incompatible sandbox capabilities,
a second update path, and confusion over which build supports extensions.

**Instead.** Download Ode from odebrowser.com. It checks for, downloads and
installs its updates on its own.

Recorded in [Distribution](Distribution.md).

## "Offer a WebKit-only download"

**Reason.** The same decision: the one Mac app ships both engines, Chromium
and WebKit, so there is one download, one update path and one answer to
which build supports extensions.

**Instead.** Use WebKit inside Ode. Settings > Engines sets the engine new
pages open in, Site Controls makes a site always open in WebKit, and Page >
Open Page in WebKit moves a single page. See
[Chromium and WebKit](../HelpCenter/docs/browsing/engines.md).

Recorded in [Distribution](Distribution.md).

## "Make Ode run on an Intel Mac"

**Reason.** Ode supports Apple silicon only, and needs macOS 26.1 or later.
The app, its native core and the prebuilt Chromium engine are all built for
arm64 alone (`ARCHS` in `project.yml`, the core's `osx-arm64` runtime and the
engine's `target_cpu` in `CrestEngines/Chromium/source.lock.json`).

**Instead.** There is no Intel build. On an Apple silicon Mac, Settings >
Advanced > Export Now writes `Ode Bookmarks.html`, a standard bookmarks file
that browsers on any Mac import.

Recorded in [Architecture](ARCHITECTURE.md), [Distribution](Distribution.md)
and the [install guide](../HelpCenter/docs/getting-started/install-and-update-mac.md).

## "Build an AI assistant into Ode"

**Reason.** Ode does not provide a page-chat or page-summary assistant.
Its optional intelligence features stay off until the person enables them.
Private answers in the Command Bar use Apple's on-device model and only what
the person types. Tab organization separately tidies titles and suggests
folders with the model the person chooses: Apple's model, a model server on
the same Mac, or ChatGPT. Choosing ChatGPT sends the relevant tab titles and
names to OpenAI. Written help answers come from the help guides.

**Instead.** Enable private answers in Settings > Search > Ode, or type an
assistant's name in the Command Bar and press Tab to use its website. A
website shortcut does not enable Ode's intelligence features. Coding agents
can connect separately through the bundled `ode-browser` helper, limited to
the Spaces the person allows. See [Intelligence](../HelpCenter/docs/browsing/intelligence.md),
[the Command Bar](../HelpCenter/docs/browsing/command-palette.md) and
[coding agents](../HelpCenter/docs/browsing/coding-agents.md).

Recorded in the [README](../README.md), [Answers](Answers.md) and those
guides.

## "Add an Ode account and a sync server"

**Reason.** Ode needs no account: tabs, history and passwords are kept on
the Mac. Sync between Macs is built on iCloud through CloudKit, with
passwords left in the Keychain, rather than on a server Ode runs. It is not
available yet, because it waits for Apple to approve Ode's iCloud access.

**Instead.** To move to another Mac now, use Export Now and Import Browser
Data in Settings > Advanced. See
[Sync and iPhone](../HelpCenter/docs/spaces/sync-across-devices.md).

Recorded in [Architecture](ARCHITECTURE.md), the
[privacy guide](../HelpCenter/docs/privacy/content-blocking-and-site-permissions.md)
and the sync guide.
