#!/usr/bin/env node
// Verifies an import of the Arc export by reading the browser's session.sqlite and comparing
// what each space holds against migration-manifest.json. Usage:
//   verify-import.mjs <session.sqlite> [migration-manifest.json]
// Without a manifest it reports every space in the store. With one it prints a row per manifest
// space and exits 0 only when every expected count equals the found count; otherwise 1.
// The store is opened read-only and nothing is written.
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

// The checkpoint table, its part names and the stored session keys are the ones the core reads.
const CORE_PART = 'core';
const HISTORY_PREFIX = 'history.';
const MAX_DEPTH = 64;
const FALLBACK_SPACE_NAME = 'Space';
const PLACEMENTS = new Set(['pinned', 'saved', 'current']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const damaged = reason => new Error(`session store is damaged: ${reason}`);

function depth(value) {
  if (value === null || typeof value !== 'object') return 0;
  let deepest = 0;
  for (const child of Object.values(value)) deepest = Math.max(deepest, depth(child));
  return deepest + 1;
}

function parseJson(bytes, name) {
  let value;
  try {
    value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    throw damaged(`part ${name} is not UTF-8 JSON`);
  }
  if (depth(value) > MAX_DEPTH) throw damaged(`part ${name} nests deeper than ${MAX_DEPTH}`);
  return value;
}

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const text = value => (typeof value === 'string' ? value : null);

// An identity is stored bare or wrapped as {"rawValue": UUID}.
function identity(node) {
  const raw = isObject(node) ? node.rawValue : node;
  if (typeof raw !== 'string' || !UUID.test(raw)) throw damaged('a space has no valid identity');
  return raw.toUpperCase();
}

function items(node, what) {
  if (node === undefined || node === null) return [];
  if (!Array.isArray(node)) throw damaged(`${what} is not a list`);
  return node;
}

// A tab whose placement the core cannot name is saved; a native view keeps no address.
function decodeTab(value) {
  if (!isObject(value)) throw damaged('a tab is not an object');
  const native = isObject(value.nativeContent);
  const placementName = text(value.placement);
  return {
    placement: PLACEMENTS.has(placementName) ? placementName : 'saved',
    url: native ? null : text(value.url),
    savedUrl: native ? null : text(value.savedURL),
  };
}

// A folder is current only when it says so; anything else is saved.
function decodeFolder(value) {
  if (!isObject(value)) throw damaged('a folder is not an object');
  return { location: text(value.location) === 'current' ? 'current' : 'saved' };
}

function decodeSpace(value) {
  if (!isObject(value)) throw damaged('a space is not an object');
  return {
    id: identity(value.id),
    name: text(value.name) ?? FALLBACK_SPACE_NAME,
    tabs: items(value.tabs, 'tabs').map(decodeTab),
    folders: items(value.folders, 'folders').map(decodeFolder),
  };
}

// Decodes the parts the way the core does: the core part holds the session, its spaces are never
// optional, and every space has a history part beside it, or the session is incomplete.
export function decodeParts(parts) {
  if (!parts.has(CORE_PART)) throw new Error('session store holds no session (no core part)');
  const document = parseJson(parts.get(CORE_PART), CORE_PART);
  if (!isObject(document) || !Array.isArray(document.spaces)) throw damaged('the session has no spaces list');
  const spaces = document.spaces.map(decodeSpace);
  for (const space of spaces) {
    const name = HISTORY_PREFIX + space.id;
    if (!parts.has(name)) throw damaged(`space ${space.name} has no ${name} part`);
    if (!Array.isArray(parseJson(parts.get(name), name))) throw damaged(`part ${name} is not a list`);
  }
  return spaces;
}

export function readParts(file) {
  if (!existsSync(file)) throw new Error(`no session store at ${file}`);
  const database = new DatabaseSync(file, { readOnly: true });
  try {
    const rows = database.prepare('SELECT part, data FROM checkpoint').all();
    return new Map(rows.map(row => [row.part, typeof row.data === 'string' ? Buffer.from(row.data, 'utf8') : row.data]));
  } finally {
    database.close();
  }
}

// The address a tab stands for: the one it was saved at, else the one it shows.
const tabAddress = tab => tab.savedUrl ?? tab.url;

export function summarize(spaces) {
  return spaces.map(space => ({
    name: space.name,
    pinnedOrSavedTabs: space.tabs.filter(tab => tab.placement !== 'current').length,
    currentTabs: space.tabs.filter(tab => tab.placement === 'current').length,
    folders: space.folders.length,
    urls: space.tabs.map(tabAddress).filter(url => url !== null),
    addresses: new Set(space.tabs.flatMap(tab => [tab.url, tab.savedUrl]).filter(url => url !== null).map(normalize)),
  }));
}

export const readStore = file => summarize(decodeParts(readParts(file)));

function normalize(url) {
  try {
    return new URL(url).href;
  } catch {
    return url;
  }
}

const unescape = value => value.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

export const bookmarkUrls = html => [...html.matchAll(/<A HREF="([^"]*)"/gi)].map(match => unescape(match[1]));

// The import places favorites as pinned tabs, the pinned section as saved tabs and Today as current
// tabs. Pinned overflows into saved, so the two are compared together.
export function expectedCounts(entry) {
  const expected = entry.expected ?? {};
  return {
    pinnedOrSavedTabs: (expected.pinnedTabs ?? 0) + (expected.favoriteTabs ?? 0),
    currentTabs: expected.todayTabs ?? 0,
    folders: expected.folders ?? 0,
  };
}

const COUNTS = ['pinnedOrSavedTabs', 'currentTabs', 'folders'];

// Matches each manifest space to the first store space with the same title not matched yet.
export function compare(store, manifest, manifestDir) {
  const unmatched = [...store];
  const rows = (manifest.spaces ?? []).map(entry => {
    const index = unmatched.findIndex(space => space.name === entry.title);
    const found = index < 0 ? null : unmatched.splice(index, 1)[0];
    const expected = expectedCounts(entry);
    const ok = found !== null && COUNTS.every(key => expected[key] === found[key]);
    let missing = null;
    const file = typeof entry.file === 'string' && path.basename(entry.file) === entry.file ? path.join(manifestDir, entry.file) : null;
    if (file && existsSync(file)) {
      const present = found?.addresses ?? new Set();
      missing = [...new Set(bookmarkUrls(readFileSync(file, 'utf8')))].filter(url => !present.has(normalize(url)));
    }
    return { title: entry.title, expected, found, ok, missing };
  });
  return { rows, ok: rows.every(row => row.ok) };
}

const counts = values => COUNTS.map(key => `${key}=${values[key]}`).join(' ');

export function formatStore(store) {
  return store.map(space => [
    `${space.name}: pinnedOrSaved=${space.pinnedOrSavedTabs} current=${space.currentTabs} folders=${space.folders}`,
    ...space.urls.map(url => `  ${url}`),
  ].join('\n')).join('\n');
}

export function formatComparison({ rows, ok }) {
  const lines = rows.map(row => {
    const head = `${row.ok ? 'OK  ' : 'FAIL'} ${row.title}: expected ${counts(row.expected)}; found ${row.found ? counts(row.found) : 'no space with this title'}`;
    const missing = (row.missing ?? []).map(url => `  missing ${url}`);
    return [head, ...missing].join('\n');
  });
  lines.push(ok ? 'import complete' : 'import incomplete');
  return lines.join('\n');
}

export function main(args) {
  const [storePath, manifestPath] = args;
  if (!storePath) {
    console.error('usage: verify-import.mjs <session.sqlite> [migration-manifest.json]');
    return 1;
  }
  const store = readStore(storePath);
  console.log(formatStore(store));
  if (!manifestPath) return 0;
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const result = compare(store, manifest, path.dirname(manifestPath));
  console.log(formatComparison(result));
  return result.ok ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === new URL(import.meta.url).pathname) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
