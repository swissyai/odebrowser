---
title: Chromium and WebKit
description: What Ode's two engines are for, how to choose the default, open a page or site in the other engine, and watch protected video.
slug: /engines
keywords: [engine, Chromium, WebKit, privacy, default engine, website rules, Open Page in WebKit, protected video, DRM, Netflix, Widevine, FairPlay, third-party cookies]
---

# Chromium and WebKit

## Why Ode has two engines, Chromium and WebKit {#engines-explained}

Chromium is the engine behind Chrome. It runs Chrome extensions and is the default. WebKit is the engine behind Safari. It offers Reader and protected video where a site supports Safari. Your tabs, Spaces and passwords are the same in both, but each keeps its own sign-ins.

## What each engine can do

| | Chromium | WebKit |
| --- | --- | --- |
| Chrome Web Store extensions | Yes | No |
| Reader | No | Yes |
| Ad and tracker blocking | Ode's own blocker | Ode's own blocker |
| Protected video | Opens in WebKit when supported | Yes, where the site supports Safari |
| Third-party cookies | Allowed, except in private windows | Limited by WebKit's tracking prevention |
| Find in Page | Shows how many matches | Shows whether there's a match |
| Save Web Archive | .mhtml file | .webarchive file |
| Inspect a page | Chromium DevTools | Web Inspector |

Tabs, Spaces, Split View, Peek, Boosts, Ode Passwords, site permissions, Picture in Picture and downloads work on both.

Chromium starts the first time a page needs it, and then runs until you quit Ode. Ode's Chromium sends Google none of your browsing, form or account data. Its background update services contact Google for certificate checks, download warnings and extensions.

## Choose the engine new pages open in {#default-engine}

1. Choose Ode > Settings, then click Engines.
2. Under Default engine, choose Chromium or WebKit. Pages already open keep their engine.

## Open a page in the other engine {#open-page-in-other-engine}

1. Choose Page > Open Page in WebKit, or Open Page in Chromium.
2. The page reloads in that engine. Other pages keep theirs.

## Always open a site in one engine {#site-engine-rule}

1. Click Site Controls and change Opens in to the engine you want.
2. To see or remove these rules, choose Ode > Settings and click Engines.

A rule for a site doesn't cover its subdomains.

Google Meet (meet.google.com), Microsoft Teams (teams.microsoft.com and teams.live.com) and Slack (app.slack.com) open in Chromium by default, because a WebKit page can't share a tab with its sound in a call. These are ordinary rules: remove one in Settings > Engines and it stays removed.

## Watch Netflix and other protected video {#protected-video}

Ode’s Chromium does not include Widevine. Supported protected video uses WebKit.

Choose Page > Open Page in WebKit to try the current page there.

Use Site Controls to keep opening that site in WebKit.

Ode’s Chromium does not include Widevine. Netflix, Disney+, Max and Prime Video open in WebKit unless you have chosen another engine for the site. When another page requests protected video that Chromium cannot play, Ode can move it to WebKit after checking for unsaved changes. Later visits to that site open in WebKit too. Click Move Back if you change your mind.

Playback still depends on the site supporting Safari.

## What the small mark on a tab's icon means {#engine-mark-on-tab}

The mark shows the tab runs in the engine that isn't your default. A blue globe means Chromium. Stacked tiles mean WebKit.

## Current limits on Chromium pages

- Ode doesn't fill addresses or payment cards.
- Sites can show notifications only while Ode is open.
- Screen sharing offers tabs in the same Space first. Choosing a window or the whole screen shares no sound.
