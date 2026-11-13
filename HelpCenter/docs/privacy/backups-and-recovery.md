---
title: Backups and recovery
description: Get your tabs back from an earlier copy, start Ode in safe mode, find crash reports, and export your data.
slug: /backups-and-recovery
keywords: [restore, earlier copy, lost tabs, backup, export, safe mode, crash report, Ode Export, bookmarks HTML]
---

# Backups and recovery

Ode keeps copies of your tabs on your Mac and writes an export you can open in other apps, so you can always get back to where you were.

## Get your tabs back

### Get your tabs back from an earlier copy {#restore-earlier-copy}

1. Choose File > Restore from an Earlier Copy.
2. Pick a copy by its date, Spaces and tab count, then click Restore and reopen.
3. Ode quits and opens again with that copy. Your current tabs are kept as a copy too.

Ode keeps a copy each time it starts and before each update.

Ode keeps a copy each time it starts, a copy before each update and each restore, and one from each of the last seven days. Each copy in the list says when and why it was kept.

### What “Some tabs are missing” means {#missing-tabs-banner}

Ode shows this when many Spaces or tabs vanished without you closing them. Click Restore that copy to go back to the earlier copy, or Keep this session if you closed them yourself.

If you closed a tab yourself, it's quicker to find it in Archive. See [History and Archive](../history-archive-and-downloads/#show-archive).

## When Ode won't start

### Ode won't open or keeps crashing at startup {#ode-wont-start}

1. Hold Shift while you open Ode, then choose Start in safe mode. Ode offers this by itself after two failed starts.
2. Safe mode pauses sync and loads pages only when you open them. Nothing is deleted.
3. If that fails too, choose Restore from an earlier copy.

### Find a crash report to share {#crash-reports}

1. Choose Ode > Settings, then click About.
2. Under Crash and hang reports, click View on a report.
3. Use Copy report or Save report… to share it.

Reports stay on your Mac for 30 days and never include the pages you visit. Ode can't send them for you yet.

## Export your data

### Ode backs up your tabs every day {#automatic-export}

Ode writes your Spaces, tabs, bookmarks and history to Documents > Ode Export every day, and soon after you change your pinned tabs or folders. It keeps the last 7 exports. Passwords and cookies are never written. Change it in Settings > Advanced > Automatic export.

Exports wait while any Space is locked.

Each export is a dated folder with three files: Ode Browser Data.json with your Spaces, tabs, folders, Archive, history and Boosts; Ode Bookmarks.html, which other browsers can import; and Ode History.jsonl.

### Export your tabs and bookmarks {#export-now}

1. Choose Ode > Settings, then click Advanced.
2. Click Export Now for a full export, or Export Bookmarks as HTML… for a file other browsers can import.

Exports never include passwords, cookies, website data or extensions.

### Bring back Spaces from an Ode export {#import-ode-export}

1. Choose Ode > Settings, then click Advanced.
2. Click Import Browser Data… and choose the Ode Browser Data.json file.
3. Its Spaces are added after yours.
