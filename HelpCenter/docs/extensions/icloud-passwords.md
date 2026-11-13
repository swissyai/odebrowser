---
title: iCloud Passwords in Ode
description: How the iCloud Passwords extension connects to Apple's password helper in Ode for Mac, and what Apple requires.
slug: /icloud-passwords
sidebar_label: iCloud Passwords
sidebar_position: 11
keywords: [iCloud Passwords, Password AutoFill, managed entitlement, Web Browser Public Key Credential Requests]
---

# iCloud Passwords in Ode

The iCloud Passwords extension installs from the Chrome Web Store into Ode for Mac and runs on Chromium pages. It is only half of iCloud Passwords. The other half is Apple's system password helper, which the extension reaches through native messaging.

## How the extension finds Apple's helper

Apple registers its helper for Google Chrome. Ode checks Chrome's native-messaging folders when Chromium's own lookup finds nothing, so the extension can reach it. Chromium still checks that the helper allows this extension. Ode does not read your passwords; Apple's helper controls authentication and access to them.

## What Apple checks

Apple protects its helper with a launch constraint on the browser. The browser must carry the managed **Web Browser Public Key Credential Requests** capability, or use an identity Apple has approved. The entitlement is:

```text
com.apple.developer.web-browser.public-key-credential
```

Direct Mac builds do not carry this capability yet. Apple approval is still pending, so installing a signed Ode build does not enable iCloud Passwords pairing. Adding the entitlement yourself does not authorize it; Apple checks the app's provisioning.

## If it does not pair

- Check Ode’s [current passkey support](../ode-passwords-per-space/#passkeys). Pairing requires Apple approval for the browser.
- Reinstalling the extension does not change the browser's signature or entitlements.
- Until it pairs, use Ode's built-in passwords for the Space or another password manager.

## Official reference

- [Web Browser Public Key Credential entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
