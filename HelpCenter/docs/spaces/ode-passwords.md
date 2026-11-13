---
title: Passwords
description: See, save, import and export passwords in each Space, keep them in iCloud Keychain, and use a password manager extension.
slug: /ode-passwords-per-space
sidebar_label: Passwords
keywords: [passwords, Ode Passwords, saved passwords, import passwords, export passwords, CSV, iCloud Keychain, strong password, 1Password, Bitwarden, passkeys]
---

# Passwords

Ode Passwords keeps the passwords you save in each Space apart from every other Space. They're kept in your Mac's Keychain and never written to Ode's exports.

## See your saved passwords {#saved-passwords}

1. Choose Ode > Settings, click the Space, then click Passwords.
2. Click an account to see it. Ode asks for Touch ID or your Mac password before showing or copying a password.

Each Space has its own passwords. The Spaces of a [Sub-Space](../sub-spaces/) group share one set of passwords and their password settings.

A revealed password hides again after 30 seconds, and a copied one is cleared from the clipboard after 60 seconds.

## Make a strong password for a new account {#strong-password}

1. Click into the password field of a sign-up form. Ode offers a strong password.
2. Click Use Strong Password. Ode saves it in the Space first, then fills it in.

## Stop Ode from offering to save passwords {#ode-passwords-off}

1. Choose Ode > Settings, click the Space, then click Passwords.
2. Turn off Use Ode Passwords. Saved passwords stay until you delete them.

## Import passwords from a file {#import-passwords}

1. Export your passwords as a CSV file from the other app.
2. Choose Ode > Settings, click the Space, click Passwords, then click Import Passwords.
3. Choose the file, review the accounts and import. Then delete the CSV file.

Ode reads Chrome-style, Safari, Firefox and Bitwarden CSV files.

## Export your passwords {#export-passwords}

1. Choose Ode > Settings, click the Space, then click Passwords.
2. Click Export Passwords… and confirm with Touch ID or your Mac password.
3. Anyone with the file can read it, so delete it once you've used it.

## Keep Ode passwords in iCloud Keychain {#passwords-icloud-keychain}

1. Choose Ode > Settings, click the Space, then click Passwords.
2. Turn on Sync with iCloud Keychain.
3. Turn on Offer a copy to Passwords to also let Apple's Passwords app save new passwords.

## Use a password manager

1Password, Bitwarden and other password managers work as Chrome extensions, on pages that open in Chromium. See [Set up 1Password and other password managers](../onepassword/).

## Sign in with passkeys {#passkeys}

Ode for Mac can't use the passkeys saved on your Mac yet. It's waiting for Apple's approval. Sign in with a password for now. Check the status in Settings > Privacy & Permissions > Passkeys.

### Moving from another browser

Browser imports and password CSV files do not transfer passkeys. Importing an active sign-in also does not copy the passkey used to create it.

If you want to change password managers, use their supported passkey transfer flow. For example, [1Password supports direct imports from Apple Passwords on iOS and iPadOS 26 or later](https://support.1password.com/import/). Support differs by provider and platform; this is separate from Ode’s browser import.

If a passkey cannot be transferred, keep the original browser or device available. Use the website’s account settings to add another sign-in method, and test it before removing the old one.

## Fill in addresses and credit cards {#autofill-cards-addresses}

Ode doesn't fill in addresses or payment cards, and doesn't offer Apple Pay on websites yet. A password manager extension that fills cards works on Chromium pages.
