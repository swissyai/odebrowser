---
title: Set up 1Password and other password managers
description: Install the 1Password Chrome extension in Ode for Mac and authorize Ode in the 1Password app.
slug: /onepassword
sidebar_label: 1Password setup
sidebar_position: 10
keywords: [1Password, native messaging, trusted browser, Add Browser, authorize Ode, Ode for Mac]
---

# Set up 1Password and other password managers

## Use 1Password, Bitwarden or another password manager {#password-manager-extension}

1. Install its extension from the Chrome Web Store in each Space you use it in.
2. For 1Password, also allow Ode in the 1Password app when it asks.

Extensions run only on pages that open in Chromium.

Bitwarden, Proton Pass, Dashlane and other managers install the same way, from their Chrome Web Store page. The rest of this page covers 1Password, whose Mac app must trust Ode as a browser before it unlocks and fills.

:::caution Use the signed Ode release
1Password checks the browser's code signature. Use the Developer ID signed and notarized Ode release installed in `/Applications`. A development build carries a different signature, and 1Password rejects it.
:::

## Before you begin

- Install and unlock **1Password for Mac**.
- Switch to the Ode Space that should own the extension. Installations do not copy to another Space or device on their own.

## Install the extension

1. In Ode for Mac, open the 1Password page in the Chrome Web Store.
2. Select the store's install button.
3. Review the package, its permissions and the destination Space in Ode's review sheet.
4. Select **Add Extension**, then **Done**.

## Authorize Ode in 1Password

1. Open and unlock **1Password for Mac**.
2. Select your account or collection at the top of the sidebar, then select **Settings**.
3. Select **Browser** in the sidebar.
4. Select **Add Browser**.
5. Choose **Ode** in `/Applications`.
6. Review 1Password's access prompt and select **Authorize**.

1Password warns that an additional browser can reach your saved information while 1Password is unlocked, so it can save and fill logins. Only authorize an Ode build you trust.

## If it does not connect

Reinstalling the extension does not change the signature 1Password checks. Confirm that you added the Ode app in `/Applications`, then see [Native companions](./native-companion-limits.md) and [Troubleshoot an extension](./troubleshoot-partial-compatibility.md).

## Official references

- [Connect additional browsers to the 1Password app](https://support.1password.com/additional-browsers/)
- [1Password browser code-signature requirements](https://support.1password.com/code-signature/)
