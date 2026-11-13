---
title: Route links to the right Space
description: Send links you click in other apps, such as Slack or Mail, to the Space that should open them.
slug: /link-routing
keywords: [link routing, Air Traffic Control, routes, links from other apps, Space, rules]
---

# Route links to the right Space

Link routing is Ode's version of Arc's Air Traffic Control. A route sends links you click in other apps to a chosen Space, so a work link opens with your work sign-ins.

## Send links from other apps to the right Space {#link-routing}

1. Choose Ode > Settings, click Links, then click New Route under Routing.
2. Choose Contains or Is Exactly and type part of the address, such as github.com.
3. Pick the Space under Open in Space. The first matching route wins.

Routes apply to links you click in other apps, not links inside Ode.

## Get routes right

- Is Exactly matches one whole address. Contains matches any address with your text in it, such as a domain.
- Start narrow, such as github.com/your-company, and test it by clicking a link in another app.
- Routes run in order from the top. Use the route's menu to move it up or down, or to delete it.
- A route to a locked Space stays hidden until you unlock that Space.

When no route matches, Ode opens the link in the Space you picked for that site before, if Remember the chosen Space for each site is on, or else as Links from other apps says. See [Peek, Quick Window and links](../peek-and-quick-window/#links-from-other-apps).
