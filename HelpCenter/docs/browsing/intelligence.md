---
title: Intelligence
description: Set up Apple's on-device model for private answers in Ode, and fix language or model download issues.
slug: /intelligence
keywords: [intelligence, AI, Apple Intelligence, on-device model, Ollama, local model, ChatGPT, tidy titles, Tidy tabs]
---

import GuideScreenshot from '@site/src/components/GuideScreenshot';

# Intelligence

Private answers use **Apple’s on-device model** and only what you type. Search suggestions still use your search service.

## Set up Apple Intelligence {#apple-intelligence-setup}

Use a compatible device with its language and Siri language set to the same supported language. [Check Apple’s device, language and region requirements](https://support.apple.com/en-us/121115).

<GuideScreenshot
  src="/img/guides/intelligence/apple-setup.svg"
  alt="In macOS 26 System Settings or iOS and iPadOS 26 Settings, open Apple Intelligence & Siri. Wait for Apple’s model, then enable Answers in the command bar in Ode’s Search settings."
  caption="Setup diagram for OS 26. Apple Intelligence is automatically available on eligible devices with OS 27."
/>

### Mac

Ode requires macOS 26.1 or later. On macOS 26, open **System Settings > Apple Intelligence & Siri**, then use the button beside **Apple Intelligence** or **Turn on Apple Intelligence** if it’s off. The label depends on your version and previous setup. [Apple’s macOS 26 instructions](https://support.apple.com/guide/mac-help/get-started-with-apple-intelligence-mchl46361784/26/mac/26).

### iPhone and iPad

Ode requires iOS or iPadOS 26.1 or later. On OS 26, open **Settings > Apple Intelligence & Siri** and use the button beside **Apple Intelligence** or **Turn on Apple Intelligence** if it’s off. [Apple’s iPhone instructions](https://support.apple.com/guide/iphone/aside/iph3212e4900/26/ios/26) · [iPad instructions](https://support.apple.com/guide/ipad/aside/ipad0ad254dc/26/ipados/26).

With macOS, iOS or iPadOS 27, Apple Intelligence is [automatically available on eligible devices](https://support.apple.com/en-us/121115). Apple’s other AI features don’t change how Ode’s private answers work.

### Turn on answers in Ode

Apple supplies and manages the system model; Ode’s installer doesn’t include it. Downloads use device storage. Once Ode shows **Available**, open **Ode Settings > Search > Ode** and turn on **Answers in the command bar**.

Private answers are **off by default**. Calculations and conversions work without enabling them. Private answers use only Apple’s on-device system model, with no cloud provider, API key or separate server. Answers can be wrong, so check important information.

### Not ready yet? {#apple-intelligence-not-ready}

- **Model downloading or not ready:** connect to power and Wi-Fi, allow time and check free storage. Ode can’t force Apple’s download. Try again after it finishes.
- **Language unavailable:** check that device and Siri languages match and are supported. A language change may need another download.
- **Not eligible or still unavailable:** check Apple’s requirements above. You can leave private answers off and keep using search, calculations and conversions.

## Does Ode use AI? {#intelligence-off}

Tab organization is off until you turn on Enable suggestions in Settings > Search > Tab organization.

When it's on, it only tidies tab titles and suggests folders for open tabs. It can run on your Mac only, with nothing sent to an AI service.

Private answers in Command-T use Apple’s on-device model and are enabled separately in Settings > Search > Ode. Written help answers come from these guides, not an AI model.

## Organize tabs with AI {#turn-on-intelligence}

1. Choose Ode > Settings, then click Search.
2. Under Tab organization, turn on Enable suggestions.
3. Pick a Tab organization model: Apple on-device model, Model on this Mac, or ChatGPT with your own plan.

Choose **Apple on-device model** to keep tab organization on your Mac. Use the setup steps above if it isn’t available. With ChatGPT, the tab titles a feature works on are sent to OpenAI.

The Tab organization model never changes the model used for private answers.

### What tab organization does {#what-intelligence-does}

Tab organization can tidy titles when pinning or saving. Tidy Title and Restore Original Title are in a pinned or saved tab’s Edit Tab menu. Sidebar Tidy suggests folders and finds duplicates; nothing changes until you click Apply.

## What each model sends

For **tab organization only**:

- **Apple on-device model:** runs on your Mac; nothing is sent to an AI service.
- **Model on this Mac:** uses a model server you run locally, such as Ollama.
- **ChatGPT:** sends tab titles and names to OpenAI using your plan.

AI Websites switches only add [website shortcuts](../command-palette/#ask-ai-from-command-bar). They don’t enable private answers or tab organization.

To skip AI answers in search results, see [Hide AI answers in Google and other search results](../command-palette/#hide-ai-overviews).
