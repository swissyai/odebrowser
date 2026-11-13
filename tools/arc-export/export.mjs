#!/usr/bin/env node
// Exports an Arc sidebar and archive into portable JSON, a combined bookmarks HTML
// file, one bookmarks HTML file per space, a single archive bookmarks file and a
// migration manifest with the expected counts per space. Reads StorableSidebar.json
// and StorableArchiveItems.json; writes nothing into Arc's directory. Every space keeps its profile directory, favorites, pinned tree
// and unpinned tabs; archived items keep their reason, time and origin space.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import path from 'node:path';

const TAB = 'tab';
const ARC_EPOCH_OFFSET_SECONDS = 978307200; // Apple reference date (2001-01-01) to Unix epoch

export function pairs(list) {
  // Arc stores several lists as alternating "<id>", {object} entries.
  const out = [];
  for (let index = 0; index < (list ?? []).length; index += 1) {
    const entry = list[index];
    if (entry && typeof entry === 'object' && !Array.isArray(entry)) out.push(entry);
  }
  return out;
}

export function profileDirectory(profile) {
  if (profile === true || profile === 'default' || (profile && typeof profile === 'object' && 'default' in profile)) return 'Default';
  const custom = profile?.custom?._0;
  return custom?.directoryBasename ?? null;
}

const countNodes = (nodes, type) => nodes.reduce((sum, entry) => sum + (entry.type === type ? 1 : 0) + (entry.children ? countNodes(entry.children, type) : 0), 0);

const toIso = seconds => Number.isFinite(seconds) ? new Date((seconds + ARC_EPOCH_OFFSET_SECONDS) * 1000).toISOString() : null;

function node(items, id, seen) {
  const item = items.get(id);
  if (!item || seen.has(id)) return null;
  seen.add(id);
  const data = item.data ?? {};
  if (data.tab) {
    return { type: 'tab', title: item.title || data.tab.savedTitle || '', savedTitle: data.tab.savedTitle ?? '', url: data.tab.savedURL ?? '', createdAt: toIso(item.createdAt), lastActiveAt: toIso(data.tab.timeLastActiveAt), unread: item.isUnread === true };
  }
  if (data.list !== undefined) {
    const live = data.list?.automaticLiveFolderData;
    return { type: 'folder', title: item.title || '', live: live ? Object.keys(live.dataSource ?? {})[0] ?? 'unknown' : null, children: (item.childrenIds ?? []).map(child => node(items, child, seen)).filter(Boolean) };
  }
  if (data.splitView !== undefined) {
    return { type: 'split', children: (item.childrenIds ?? []).map(child => node(items, child, seen)).filter(Boolean) };
  }
  return null;
}

function containerChildren(items, containerId, seen) {
  const container = items.get(containerId);
  if (!container) return [];
  seen.add(containerId);
  return (container.childrenIds ?? []).map(child => node(items, child, seen)).filter(Boolean);
}

function markerName(marker) {
  if (typeof marker === 'string') return marker;
  if (marker && typeof marker === 'object') return Object.keys(marker)[0] ?? 'unknown';
  return 'unknown';
}

export function exportSidebar(sidebar) {
  const container = (sidebar.sidebar?.containers ?? []).find(entry => entry && typeof entry === 'object' && 'spaces' in entry);
  if (!container) throw new Error('no sidebar container with spaces');
  const items = new Map(pairs(container.items).filter(item => item.id).map(item => [item.id, item]));
  const seen = new Set();
  const favorites = {};
  const topApps = container.topAppsContainerIDs ?? [];
  for (let index = 0; index + 1 < topApps.length; index += 2) {
    favorites[profileDirectory(topApps[index]) ?? 'unknown'] = containerChildren(items, topApps[index + 1], seen);
  }
  const spaces = pairs(container.spaces).map(space => {
    const sections = {};
    const ids = space.containerIDs ?? space.newContainerIDs ?? [];
    for (let index = 0; index + 1 < ids.length; index += 2) sections[markerName(ids[index])] = containerChildren(items, ids[index + 1], seen);
    const profile = profileDirectory(space.profile);
    return { id: space.id, title: space.title ?? '', profile, icon: space.customInfo?.iconType ?? null, favorites: favorites[profile ?? 'unknown'] ?? [], pinned: sections.pinned ?? [], unpinned: sections.unpinned ?? [] };
  });
  const unreached = [...items.values()].filter(item => !seen.has(item.id) && item.data?.tab).map(item => ({ title: item.title || item.data.tab.savedTitle, url: item.data.tab.savedURL }));
  const counts = {
    spaces: spaces.length,
    tabs: spaces.reduce((sum, space) => sum + countNodes(space.pinned, TAB) + countNodes(space.unpinned, TAB), 0) + Object.values(favorites).reduce((sum, nodes) => sum + countNodes(nodes, TAB), 0),
    pinnedTabs: spaces.reduce((sum, space) => sum + countNodes(space.pinned, TAB), 0),
    unpinnedTabs: spaces.reduce((sum, space) => sum + countNodes(space.unpinned, TAB), 0),
    favoriteTabs: Object.values(favorites).reduce((sum, nodes) => sum + countNodes(nodes, TAB), 0),
    folders: spaces.reduce((sum, space) => sum + countNodes(space.pinned, 'folder') + countNodes(space.unpinned, 'folder'), 0),
    itemsInFile: items.size,
    unreachedTabs: unreached.length,
  };
  return { version: 1, exportedAt: new Date().toISOString(), spaces, favoritesByProfile: favorites, unreached, counts };
}

export function exportArchive(archive) {
  const entries = pairs(archive?.items).map(entry => {
    const tab = entry.sidebarItem?.data?.tab ?? entry.sidebarItem?.tab ?? null;
    return { title: entry.sidebarItem?.title || tab?.savedTitle || '', url: tab?.savedURL ?? null, archivedAt: toIso(entry.archivedAt), reason: typeof entry.reason === 'string' ? entry.reason : Object.keys(entry.reason ?? {})[0] ?? null, source: typeof entry.source === 'string' ? entry.source : Object.keys(entry.source ?? {})[0] ?? null, spaceId: entry.source?.space?._0 ?? entry.source?.space ?? null };
  }).filter(entry => entry.url);
  return { version: 1, count: entries.length, entries };
}

const escape = value => String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
function htmlNodes(nodes, depth) {
  const pad = '    '.repeat(depth);
  return nodes.map(entry => {
    if (entry.type === 'tab') return `${pad}<DT><A HREF="${escape(entry.url)}">${escape(entry.title || entry.url)}</A>`;
    const children = entry.children ?? [];
    const title = entry.type === 'split' ? 'Split view' : entry.title || 'Folder';
    return `${pad}<DT><H3>${escape(title)}</H3>\n${pad}<DL><p>\n${htmlNodes(children, depth + 1)}\n${pad}</DL><p>`;
  }).join('\n');
}

function spaceSection(space) {
  const parts = [];
  if (space.favorites.length) parts.push(`        <DT><H3>Favorites</H3>\n        <DL><p>\n${htmlNodes(space.favorites, 3)}\n        </DL><p>`);
  parts.push(`        <DT><H3>Pinned</H3>\n        <DL><p>\n${htmlNodes(space.pinned, 3)}\n        </DL><p>`);
  if (space.unpinned.length) parts.push(`        <DT><H3>Today</H3>\n        <DL><p>\n${htmlNodes(space.unpinned, 3)}\n        </DL><p>`);
  return `    <DT><H3>${escape(space.title || space.id)}</H3>\n    <DL><p>\n${parts.join('\n')}\n    </DL><p>`;
}

const archiveSection = archive => `    <DT><H3>Archive</H3>\n    <DL><p>\n${archive.entries.map(entry => `        <DT><A HREF="${escape(entry.url)}" ADD_DATE="${entry.archivedAt ? Math.floor(Date.parse(entry.archivedAt) / 1000) : ''}">${escape(entry.title || entry.url)}</A>`).join('\n')}\n    </DL><p>`;

const bookmarksDocument = sections => `<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n<TITLE>Bookmarks</TITLE>\n<H1>Bookmarks</H1>\n<DL><p>\n${sections.join('\n')}\n</DL><p>\n`;

export function bookmarksHtml(exported, archive) {
  const sections = exported.spaces.map(spaceSection);
  if (archive?.entries?.length) sections.push(archiveSection(archive));
  return bookmarksDocument(sections);
}

// One importable file per space: that space's favorites, pinned tree and today tabs only.
export const spaceBookmarksHtml = space => bookmarksDocument([spaceSection(space)]);

// The archive belongs to no single space, so it gets its own file and never appears in a space file.
export const archiveBookmarksHtml = archive => bookmarksDocument(archive?.entries?.length ? [archiveSection(archive)] : []);

export const ARCHIVE_BOOKMARKS_FILE = 'arc-archive.html';

// Space ids become file names; anything outside a conservative set is replaced so an id cannot escape the output directory.
export const spaceBookmarksFile = space => `arc-space-${String(space.id ?? 'unknown').replace(/[^A-Za-z0-9._-]/g, '_')}.html`;

// Expected counts per space use the same counting rules as exportSidebar: tabs and folders are
// counted through nested folders and split views, and folders are counted in pinned and today only.
// Favorites belong to a profile, so spaces sharing a profile report the same favorite tabs; the
// totals are the exporter counts themselves.
export function migrationManifest(exported, archive) {
  const spaces = exported.spaces.map(space => ({
    id: space.id,
    title: space.title,
    profile: space.profile,
    file: spaceBookmarksFile(space),
    expected: { pinnedTabs: countNodes(space.pinned, TAB), todayTabs: countNodes(space.unpinned, TAB), favoriteTabs: countNodes(space.favorites, TAB), folders: countNodes(space.pinned, 'folder') + countNodes(space.unpinned, 'folder') },
  }));
  const files = spaces.map(space => space.file);
  const duplicate = files.find((file, index) => files.indexOf(file) !== index);
  if (duplicate) throw new Error(`two spaces map to the same bookmarks file ${duplicate}`);
  return {
    version: 1,
    exportedAt: exported.exportedAt,
    spaces,
    archive: { count: archive?.count ?? 0, file: ARCHIVE_BOOKMARKS_FILE },
    totals: { ...exported.counts, archived: archive?.count ?? 0 },
  };
}

export function writeExport(outDir, exported, archive) {
  const manifest = migrationManifest(exported, archive);
  mkdirSync(outDir, { recursive: true });
  const write = (name, content) => writeFileSync(path.join(outDir, name), content, { mode: 0o600 });
  write('arc-sidebar.json', `${JSON.stringify(exported, null, 1)}\n`);
  write('arc-archive.json', `${JSON.stringify(archive, null, 1)}\n`);
  write('arc-bookmarks.html', bookmarksHtml(exported, archive));
  exported.spaces.forEach((space, index) => write(manifest.spaces[index].file, spaceBookmarksHtml(space)));
  write(ARCHIVE_BOOKMARKS_FILE, archiveBookmarksHtml(archive));
  write('migration-manifest.json', `${JSON.stringify(manifest, null, 1)}\n`);
  return manifest;
}

if (process.argv[1] && path.resolve(process.argv[1]) === new URL(import.meta.url).pathname) {
  const [source = path.join(process.env.HOME, 'Library/Application Support/Arc'), outDir = process.cwd()] = process.argv.slice(2);
  const sidebar = JSON.parse(readFileSync(path.join(source, 'StorableSidebar.json'), 'utf8'));
  const archivePath = path.join(source, 'StorableArchiveItems.json');
  const archive = existsSync(archivePath) ? exportArchive(JSON.parse(readFileSync(archivePath, 'utf8'))) : { version: 1, count: 0, entries: [] };
  const exported = exportSidebar(sidebar);
  writeExport(outDir, exported, archive);
  console.log(JSON.stringify({ ...exported.counts, archived: archive.count, spaces: exported.spaces.map(space => `${space.title} (${space.profile}): ${space.pinned.length} pinned roots, ${space.unpinned.length} today, ${space.favorites.length} favorites`) }, null, 1));
}
