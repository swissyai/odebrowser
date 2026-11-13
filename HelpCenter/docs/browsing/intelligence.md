---
title: Intelligence
description: Ode's optional intelligence is off by default. Here's what it does, which models it can use, and what it sends.
slug: /intelligence
keywords: [intelligence, AI, Apple Intelligence, on-device model, Ollama, local model, ChatGPT, tidy titles, Tidy tabs]
---

# Intelligence

## Does Ode use AI {#intelligence-off}

Tab organization is off until you turn on Enable suggestions in Settings > Search > Tab organization. When it's on, it only tidies tab titles and suggests folders for open tabs. It can run on your Mac only, with nothing sent to an AI service. Private answers in Command-T use Apple’s on-device model and are enabled separately in Settings > Search > Ode.

## Turn on intelligence and choose a model {#turn-on-intelligence}

1. Choose Ode > Settings, then click Search.
2. Under Tab organization, turn on Enable suggestions.
3. Pick a Tab organization model: Apple on-device model, Model on this Mac, or ChatGPT with your own plan.

Apple’s on-device availability is shown even while intelligence is off. Local-server checks and ChatGPT account controls are available after you turn it on.

With ChatGPT, the tab titles a feature works on are sent to OpenAI.

## What intelligence does

- Tidies the titles of tabs you pin or save, while Tidy titles when pinning is on.
- Adds Tidy Title and Restore Original Title to a pinned or saved tab's Edit Tab menu.
- Adds Tidy to the line in the sidebar, which suggests folders for your open tabs and finds duplicates. Nothing changes until you click Apply.

Written help answers in the Command Bar come from these guides. The separate Ode > Answers in Command-T setting in Search enables private answers using Apple's on-device model; it does not use the Tab organization model.

## What each model sends

- Apple on-device model: runs on your Mac. Nothing is sent.
- Model on this Mac: a model you run yourself, such as one served by Ollama at http://127.0.0.1:11434/v1. Nothing leaves your Mac.
- ChatGPT: uses your own ChatGPT plan after Continue with ChatGPT. The titles and tab names a feature works on are sent to OpenAI.

The separate AI Websites switches in Search add website shortcuts to Command-T. Type a shortcut such as chatgpt, press Tab, then enter your question. The question opens on that website using your account there; the switch does not connect an account or enable Tab organization or Answers in Command-T.

To skip AI answers in search results, see [Hide AI answers in Google and other search results](../command-palette/#hide-ai-overviews).
