---
title: Manage permissions and website access per Space
description: Review and change an extension's permissions and site access without changing another Ode Space.
slug: /manage-extension-permissions
sidebar_label: Permissions & site access
sidebar_position: 4
keywords: [extension permissions, website access, site access, Space isolation]
---

# Manage permissions and website access per Space

Every Space keeps its own extension installations, permissions and website access. Allowing a tool in Work does not grant it the same access in Personal or on another Mac. The Spaces of a [Sub-Space](../spaces/sub-spaces.md) group share one installation, with its permissions and website access.

## At installation

The install review lists the permission warnings Chromium reports for the extension. Where the extension allows it, turn on **Withhold website access until I grant it** so the extension reaches a site only after you allow it. See [Install from the Chrome Web Store](./install-chrome-web-store.md).

## Review access later

1. Open **Settings** and select the Space in the sidebar.
2. Select **Extensions**.
3. Expand the extension's row to see its **Permissions and Website Access**.

## Change website access

In the expanded row, select **Manage Permissions in Chromium**. Chromium's page for that extension opens in the same Space, where you can change its site access and other permissions. The change applies only to this Space's installation, which every Space of its Sub-Space group shares.

## Use an extension in more than one Space {#extension-other-spaces}

1. Choose Ode > Settings, click the Space that has the extension, then click Extensions.
2. Expand the extension and click Install a copy in other spaces.
3. Pick the Spaces. Each copy has its own settings and data.

## Turn off or remove an extension {#remove-extension}

1. Choose Ode > Settings, click the Space, then click Extensions.
2. Turn the extension's switch off to pause it, or expand it and click Remove Extension.

Removing it from one Space leaves it in the others.

Removing an extension also removes its data from that Space. In a [Sub-Space](../spaces/sub-spaces.md) group, it leaves every Space of the group.

Private Spaces must be unlocked before Ode shows or changes their installed extensions.
