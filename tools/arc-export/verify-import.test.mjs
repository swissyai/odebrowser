import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { exportSidebar, writeExport } from './export.mjs';
import { readStore } from './verify-import.mjs';

const script = fileURLToPath(new URL('./verify-import.mjs', import.meta.url));

// Arc sidebar: Work has a favorite, a pinned folder with one tab, a pinned tab and a Today tab;
// Home has a favorite and a Today tab.
const arcTab = (id, url) => ({ id, childrenIds: [], data: { tab: { savedURL: url, savedTitle: id } } });
const arcSidebar = () => ({ sidebar: { containers: [{ global: [] }, {
  spaces: ['S1', { id: 'S1', title: 'Work', profile: { custom: { _0: { directoryBasename: 'Profile 1' } } }, containerIDs: ['pinned', 'P1', 'unpinned', 'U1'] },
    'S2', { id: 'S2', title: 'Home', profile: { default: {} }, containerIDs: ['pinned', 'P2', 'unpinned', 'U2'] }],
  topAppsContainerIDs: [{ default: true }, 'F0', { custom: { _0: { directoryBasename: 'Profile 1' } } }, 'F1'],
  items: ['P1', { id: 'P1', childrenIds: ['L1', 'T2'], data: { itemContainer: {} } }, 'L1', { id: 'L1', title: 'Docs', childrenIds: ['T1'], data: { list: {} } },
    'T1', arcTab('T1', 'https://a.example/docs'), 'T2', arcTab('T2', 'https://b.example/'),
    'U1', { id: 'U1', childrenIds: ['T3'], data: { itemContainer: {} } }, 'T3', arcTab('T3', 'https://c.example/today'),
    'F1', { id: 'F1', childrenIds: ['T4'], data: { itemContainer: {} } }, 'T4', arcTab('T4', 'https://fav.example/'),
    'P2', { id: 'P2', childrenIds: [], data: { itemContainer: {} } }, 'U2', { id: 'U2', childrenIds: ['T5'], data: { itemContainer: {} } },
    'T5', arcTab('T5', 'https://d.example/home'), 'F0', { id: 'F0', childrenIds: ['T6'], data: { itemContainer: {} } }, 'T6', arcTab('T6', 'https://e.example/')],
}] } });

// The stored session shape StoredSessionCodec writes: identities as Swift spells them, wrapped
// as {"rawValue": UUID} for typed ones, and dates as seconds since 2001.
const swiftId = () => randomUUID().toUpperCase();
const wrapped = id => ({ rawValue: id });

function storedTab(url, placement, folder = null) {
  const tab = { id: wrapped(swiftId()), title: url, url, symbol: 'globe', placement, lastActivatedAt: 800000000.0, keepsPageLoaded: false };
  if (placement !== 'current') tab.savedURL = url;
  if (folder) tab.folderID = wrapped(folder);
  return tab;
}

const storedFolder = (id, title) => ({ id: wrapped(id), location: 'saved', title, isCollapsed: false });

function storedSpace(name, folders, tabs) {
  return {
    id: wrapped(swiftId()), profile: { id: swiftId() }, name, symbol: 'square.grid.2x2.fill', accent: 'indigo',
    folders, tabs, splitGroups: [], archivedTabs: [], accessPolicy: 'open', isSavedTabsExpanded: true,
  };
}

// The import places favorites as pinned tabs, pinned Arc tabs as saved tabs and Today as current.
function importedSpaces({ dropWorkTab } = {}) {
  const docs = swiftId();
  const workTabs = [storedTab('https://fav.example/', 'pinned'), storedTab('https://a.example/docs', 'saved', docs),
    storedTab('https://b.example/', 'saved'), storedTab('https://c.example/today', 'current')]
    .filter(tab => tab.url !== dropWorkTab);
  return [storedSpace('Work', [storedFolder(docs, 'Docs')], workTabs),
    storedSpace('Home', [], [storedTab('https://e.example/', 'pinned'), storedTab('https://d.example/home', 'current')])];
}

function writeStore(file, spaces, { omitHistory = false } = {}) {
  const database = new DatabaseSync(file);
  try {
    database.exec('CREATE TABLE IF NOT EXISTS checkpoint (part TEXT PRIMARY KEY, data BLOB NOT NULL)');
    const put = database.prepare('INSERT INTO checkpoint (part, data) VALUES (?, ?)');
    put.run('core', Buffer.from(JSON.stringify({ spaces }), 'utf8'));
    if (!omitHistory) for (const space of spaces) put.run(`history.${space.id.rawValue}`, Buffer.from('[]', 'utf8'));
    put.run('journal', Buffer.from(JSON.stringify({ schemaVersion: 1, records: [] }), 'utf8'));
  } finally {
    database.close();
  }
}

function withDir(run) {
  const dir = mkdtempSync(path.join(tmpdir(), 'arc-verify-test-'));
  try { return run(dir); } finally { rmSync(dir, { recursive: true, force: true }); }
}

function exportTo(dir) {
  writeExport(dir, exportSidebar(arcSidebar()), { version: 1, count: 0, entries: [] });
  return path.join(dir, 'migration-manifest.json');
}

const verify = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });

test('reads each space from the checkpoint core part: name, pinned or saved, current, folders and tab URLs', () => withDir(dir => {
  const file = path.join(dir, 'session.sqlite');
  const spaces = importedSpaces();
  spaces[1].tabs.push({ ...storedTab('https://odd.example/', 'hibernated'), savedURL: undefined });
  spaces[1].tabs.push({ id: wrapped(swiftId()), title: 'Settings', nativeContent: { kind: 'settings' }, placement: 'current', lastActivatedAt: 1 });
  delete spaces[1].name;
  writeStore(file, spaces);
  const store = readStore(file);
  assert.deepEqual(store.map(({ addresses, ...space }) => space), [
    { name: 'Work', pinnedOrSavedTabs: 3, currentTabs: 1, folders: 1, urls: ['https://fav.example/', 'https://a.example/docs', 'https://b.example/', 'https://c.example/today'] },
    // A space without a name reads as "Space", an unknown placement as saved, and a native view has no address.
    { name: 'Space', pinnedOrSavedTabs: 2, currentTabs: 2, folders: 0, urls: ['https://e.example/', 'https://d.example/home', 'https://odd.example/'] },
  ]);
  const listed = verify(file);
  assert.equal(listed.status, 0, listed.stderr);
  assert.match(listed.stdout, /^Work: pinnedOrSaved=3 current=1 folders=1$/m);
  assert.match(listed.stdout, /^ {2}https:\/\/c\.example\/today$/m);
}));

test('a store missing a space history part or the core part is refused', () => withDir(dir => {
  const file = path.join(dir, 'session.sqlite');
  writeStore(file, importedSpaces(), { omitHistory: true });
  assert.throws(() => readStore(file), /has no history\./);
  const empty = path.join(dir, 'empty.sqlite');
  const database = new DatabaseSync(empty);
  database.exec('CREATE TABLE checkpoint (part TEXT PRIMARY KEY, data BLOB NOT NULL)');
  database.close();
  const result = verify(empty);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /no core part/);
}));

test('a full import matches the manifest for every space and exits 0', () => withDir(dir => {
  const manifest = exportTo(dir);
  const file = path.join(dir, 'session.sqlite');
  writeStore(file, importedSpaces());
  const result = verify(file, manifest);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^OK {3}Work: expected pinnedOrSavedTabs=3 currentTabs=1 folders=1; found pinnedOrSavedTabs=3 currentTabs=1 folders=1$/m);
  assert.match(result.stdout, /^OK {3}Home: expected pinnedOrSavedTabs=1 currentTabs=1 folders=0; found pinnedOrSavedTabs=1 currentTabs=1 folders=0$/m);
  assert.doesNotMatch(result.stdout, /missing/);
  assert.match(result.stdout, /^import complete$/m);
}));

test('a missing tab fails the space, names the missing URL from the space bookmarks file and exits 1', () => withDir(dir => {
  const manifest = exportTo(dir);
  const file = path.join(dir, 'session.sqlite');
  writeStore(file, importedSpaces({ dropWorkTab: 'https://b.example/' }));
  const result = verify(file, manifest);
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^FAIL Work: expected pinnedOrSavedTabs=3 currentTabs=1 folders=1; found pinnedOrSavedTabs=2 currentTabs=1 folders=1$/m);
  assert.match(result.stdout, /^ {2}missing https:\/\/b\.example\/$/m);
  assert.equal(result.stdout.match(/missing /g).length, 1);
  assert.match(result.stdout, /^OK {3}Home:/m);
  assert.match(result.stdout, /^import incomplete$/m);
}));

test('a manifest space with no space of that title in the store fails', () => withDir(dir => {
  const manifest = exportTo(dir);
  const file = path.join(dir, 'session.sqlite');
  writeStore(file, importedSpaces().slice(0, 1));
  const result = verify(file, manifest);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /^FAIL Home: .*found no space with this title$/m);
  assert.match(result.stdout, /^ {2}missing https:\/\/d\.example\/home$/m);
}));
