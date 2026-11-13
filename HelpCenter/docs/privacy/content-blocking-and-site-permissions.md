---
title: Privacy, ad blocking and site permissions
description: How Ode blocks ads and trackers, how to let a site use your camera or microphone, allow pop-ups, and fix a site that isn't working.
slug: /content-blocking-and-site-permissions
keywords: [ad blocking, content blocking, ads, trackers, filter lists, strict, block element, permissions, camera, microphone, location, pop-ups, notifications, certificate, privacy]
---

# Privacy, ad blocking and site permissions

## What Ode sends and keeps {#privacy-data}

Ode needs no account. Your tabs, history and passwords are kept on your Mac. Search suggestions send what you type to your search engine. Turn them off in Settings > Search. Intelligence and automatic update checks stay off until you turn them on.

## Ads and trackers

### How Ode blocks ads and trackers {#content-blocking}

Blocking is on in every Space from the start. Chromium and WebKit pages both use Ode's own blocker, with the filter lists ad blockers use: EasyList, EasyPrivacy and uBlock Origin's lists, plus one for your language. On WebKit pages, Site Controls shows what a page blocked.

The lists download from their makers and stay up to date on their own. Blocked ads leave no empty boxes, and floating video players are hidden.

### Choose how much Ode blocks {#ad-blocking-level}

1. Choose Ode > Settings, then click Ad Blocking.
2. Choose Off, Balanced or Strict.

Balanced blocks ads and trackers and keeps sites working. Strict also hides cookie notices and other annoyances and adds AdGuard's ad list, so a few sites may not work. Turn a single list on or off and the setting says Customized; its reset button brings back the level's lists. Update Now downloads every list again.

### Add a filter list or your own rules {#custom-filters}

1. Choose Ode > Settings, then click Ad Blocking.
2. Under Your Lists, add a list by its address. It stays up to date like the built-in ones.
3. Under My Filters, write your own rules, one per line, then click Save.

Ad blocking settings stay on this Mac and don't sync.

### Hide part of a page {#block-element}

1. Right-click what you want to hide and choose Block Element, or choose Page > Block Element and point at it.
2. Use the arrows in the bar at the bottom to pick the larger element around it or the smaller one inside.
3. Click Block. Ode adds the rule to My Filters for that site.

To bring back what you hid on a site, choose Show Blocked Elements in the same place.

### Turn off ad blocking for one site {#block-ads-site}

1. Click Site Controls at the right of the address.
2. Turn off Block ads and trackers on this site. The page reloads.

On any page, you can also choose Turn Off Blocking from the Page menu, or give Toggle Content Blocking a shortcut. The site stays unblocked in every Space until you turn blocking on again there or under Sites with Blocking Off in Settings > Ad Blocking. Turned off in a private window, it lasts until you quit Ode.

### Turn ad blocking on or off {#content-blocking-space}

1. Choose Ode > Settings, then click Ad Blocking.
2. Choose Off to stop blocking in every Space, or Balanced or Strict to turn it back on.

## What sites may do

Each Space remembers its own choices, so allowing your camera for a site in Work doesn't allow it in Personal. The Spaces of a [Sub-Space](../sub-spaces/) group share them.

### Let a site use your camera, microphone or location {#site-permissions}

1. Click Site Controls at the right of the address.
2. Under Permissions, set Camera, Microphone or Location to Allow.
3. If it still doesn't work, check that macOS allows Ode in Settings > Privacy & Permissions.

### Check that macOS lets Ode use the camera or microphone {#system-permissions}

1. Choose Ode > Settings, then click Privacy & Permissions.
2. Under System permissions, check Camera, Microphone, Location, Notifications and Files & Folders, and fix any that need it.

### Reset what you allowed or blocked for sites {#reset-site-permissions}

1. Choose Ode > Settings, click the Space, then click Privacy.
2. Under Site permissions, choose Ask Again for one site, or click Reset All… for every site.

Each Space keeps its own permissions. To sign out of a site and remove what it stored, [clear its data](./clear-website-data.md) instead.

### Allow pop-ups for a site {#allow-popups}

1. When a pop-up is blocked, a dot appears on Site Controls. Click it.
2. Click Allow Automatic Pop-ups, then try the button on the page again.

### Get or stop notifications from a site {#site-notifications}

1. Click Site Controls and set Notifications to Allow or Block.
2. Make sure macOS allows Ode's notifications in Settings > Privacy & Permissions.

Sites can notify you only while Ode is open.

Screen sharing asks every time. On Chromium pages, Ode first offers tabs from the same Space, with their sound; choose Window or Screen for the macOS picker. While a tab is shared, right-click it and choose Stop Sharing to stop.

## Safe connections

### Is this site's connection secure {#site-security}

Look at the lock at the left of the address. It says whether the connection is secure. Click it, or look under Security in Site Controls, to review the certificate.

Don't type passwords or card numbers on a page marked Not Secure.

Ode's Chromium engine doesn't use Google Safe Browsing, so it can't warn you about every known phishing site or harmful download. Certificate checks, with revocation lists Ode keeps up to date, and warnings about risky files still apply.

## When a site doesn't work

### A website isn't working properly {#page-not-loading}

1. Reload the page. If an ad blocker might be the cause, turn off Block ads and trackers on this site in Site Controls.
2. Try the other engine: choose Page > Open Page in WebKit or Open Page in Chromium.
3. Check you're in the right Space, since each Space has its own sign-ins.
