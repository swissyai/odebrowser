---
title: Native companions
description: How extensions in Ode for Mac connect to their companion Mac apps, and what those apps check.
slug: /native-companion-limits
sidebar_label: Native companions
sidebar_position: 8
keywords: [Ode for Mac, nativeMessaging, native companion, allowed_origins, password manager]
---

# Native companions

Most extensions need no desktop helper. A smaller group, with password managers the common example, uses `nativeMessaging` to talk to a separate Mac app.

## How Ode finds the helper

Extensions run on Chromium, which handles `nativeMessaging` as Chrome does. Each companion app registers a small manifest that names its helper and the extension IDs it will answer.

Most companion apps register only with Google Chrome. When Chromium's own lookup finds no manifest, Ode also checks Chrome's per-user and system `NativeMessagingHosts` folders. Chromium still checks the manifest's `allowed_origins`, so a helper answers only the extensions its app lists.

## The app decides whether to trust Ode

Some companion apps check the browser's code signature before they answer.

- **1Password** accepts a browser you add through its **Add Browser** setting, and checks that browser's signature. See [Set up 1Password in Ode](./onepassword.md).
- **iCloud Passwords** uses Apple's password helper, which Apple protects with a launch constraint on the browser's identity and entitlements. See [iCloud Passwords in Ode](./icloud-passwords.md).

Use the signed and notarized Ode release in `/Applications`. A development build carries a different signature, and companion apps that check the signature reject it.

## What Ode does not do

- Ode does not copy Chrome's profile or read a companion app's data.
- Safari app extensions and their native handlers do not work in Ode.

## Availability

Official Ode for Mac builds are signed with Developer ID, notarized, and published on [odebrowser.com](https://odebrowser.com/), with updates through a signed Sparkle appcast.
