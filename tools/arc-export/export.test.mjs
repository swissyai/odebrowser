import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { bookmarksHtml, exportArchive, exportSidebar, migrationManifest, pairs, profileDirectory, writeExport } from './export.mjs';

const tab = (id, parent, url, title) => ({ id, parentID: parent, childrenIds: [], createdAt: 800000000, data: { tab: { savedURL: url, savedTitle: title, timeLastActiveAt: 800000500 } } });
const fixture = () => ({ sidebar: { containers: [{ global: [] }, {
  spaces: ['S1', { id: 'S1', title: 'Work', profile: { custom: { _0: { directoryBasename: 'Profile 1' } } }, containerIDs: ['pinned', 'P1', { unpinned: { _0: {} } }, 'U1'] }, 'S2', { id: 'S2', title: 'Home', profile: { default: {} }, containerIDs: ['pinned', 'P2', 'unpinned', 'U2'] }],
  topAppsContainerIDs: [{ default: true }, 'F0', { custom: { _0: { directoryBasename: 'Profile 1' } } }, 'F1'],
  items: ['P1', { id: 'P1', childrenIds: ['L1', 'T2'], data: { itemContainer: {} } }, 'L1', { id: 'L1', title: 'Docs', childrenIds: ['T1'], data: { list: {} } }, 'T1', tab('T1', 'L1', 'https://a.example/docs', 'A docs'), 'T2', tab('T2', 'P1', 'https://b.example/', 'B'),
    'U1', { id: 'U1', childrenIds: ['T3'], data: { itemContainer: {} } }, 'T3', tab('T3', 'U1', 'https://c.example/today', 'C today'),
    'P2', { id: 'P2', childrenIds: ['LF'], data: { itemContainer: {} } }, 'LF', { id: 'LF', title: 'Pull Requests', childrenIds: [], data: { list: { automaticLiveFolderData: { dataSource: { github: {} } } } } }, 'U2', { id: 'U2', childrenIds: [], data: { itemContainer: {} } },
    'F0', { id: 'F0', childrenIds: ['T4'], data: { itemContainer: {} } }, 'T4', tab('T4', 'F0', 'https://fav.example/', 'Fav'), 'F1', { id: 'F1', childrenIds: [], data: { itemContainer: {} } },
    'X9', tab('X9', 'nowhere', 'https://orphan.example/', 'Orphan')],
}] } });

const archiveFixture = () => ({ items: ['A1', { archivedAt: 810000000, reason: { auto: {} }, source: { space: { _0: 'S1' } }, sidebarItem: { title: '', data: { tab: { savedURL: 'https://old.example/', savedTitle: 'Old' } } } }, 'A2', { archivedAt: 810000100, reason: 'manual', source: 'littleArc', sidebarItem: { data: { tab: { savedURL: 'https://gone.example/', savedTitle: 'Gone' } } } }] });

function withOutDir(run) {
  const dir = mkdtempSync(path.join(tmpdir(), 'arc-export-test-'));
  try { return run(dir); } finally { rmSync(dir, { recursive: true, force: true }); }
}

const sum = (spaces, key) => spaces.reduce((total, space) => total + space.expected[key], 0);

test('pairs and profiles decode the alternating id/object layout and the three profile forms', () => {
  assert.equal(pairs(['a', { id: 'a' }, 'b', { id: 'b' }]).length, 2);
  assert.equal(profileDirectory({ default: {} }), 'Default');
  assert.equal(profileDirectory(true), 'Default');
  assert.equal(profileDirectory({ custom: { _0: { directoryBasename: 'Profile 3' } } }), 'Profile 3');
});

test('every space keeps its profile, favorites, pinned tree with folders and live folders, and today tabs; orphans are reported', () => {
  const out = exportSidebar(fixture());
  assert.deepEqual(out.spaces.map(space => [space.title, space.profile]), [['Work', 'Profile 1'], ['Home', 'Default']]);
  const work = out.spaces[0];
  assert.equal(work.pinned[0].type, 'folder');
  assert.equal(work.pinned[0].title, 'Docs');
  assert.equal(work.pinned[0].children[0].url, 'https://a.example/docs');
  assert.equal(work.unpinned[0].title, 'C today');
  assert.equal(work.favorites.length, 0);
  const home = out.spaces[1];
  assert.equal(home.favorites[0].url, 'https://fav.example/');
  assert.equal(home.pinned[0].live, 'github');
  assert.deepEqual(out.counts, { spaces: 2, tabs: 4, pinnedTabs: 2, unpinnedTabs: 1, favoriteTabs: 1, folders: 2, itemsInFile: 13, unreachedTabs: 1 });
  assert.equal(out.unreached[0].url, 'https://orphan.example/');
  assert.equal(out.spaces[0].pinned[1].createdAt, new Date((800000000 + 978307200) * 1000).toISOString());
});

test('archive entries keep url, time, reason and origin; the html groups spaces into favorites, pinned, today and archive', () => {
  const archive = exportArchive(archiveFixture());
  assert.equal(archive.count, 2);
  assert.deepEqual([archive.entries[0].reason, archive.entries[0].source, archive.entries[0].spaceId], ['auto', 'space', 'S1']);
  const html = bookmarksHtml(exportSidebar(fixture()), archive);
  assert.match(html, /<H3>Work<\/H3>/);
  assert.match(html, /<H3>Pinned<\/H3>[\s\S]*<H3>Docs<\/H3>[\s\S]*A docs/);
  assert.match(html, /<H3>Today<\/H3>[\s\S]*C today/);
  assert.match(html, /<H3>Archive<\/H3>[\s\S]*Old/);
  assert.match(html, /&amp;|&lt;|https:\/\/fav\.example\//);
});

test('the migration manifest lists every space with profile and expected counts that equal the exporter counts', () => {
  const exported = exportSidebar(fixture());
  const archive = exportArchive(archiveFixture());
  const manifest = withOutDir(dir => {
    const returned = writeExport(dir, exported, archive);
    const written = JSON.parse(readFileSync(path.join(dir, 'migration-manifest.json'), 'utf8'));
    assert.deepEqual(written, returned);
    return written;
  });
  assert.deepEqual(manifest, migrationManifest(exported, archive));
  assert.deepEqual(manifest.spaces.map(space => [space.id, space.title, space.profile]), exported.spaces.map(space => [space.id, space.title, space.profile]));
  assert.deepEqual(manifest.spaces.map(space => [space.id, space.title, space.profile]), [['S1', 'Work', 'Profile 1'], ['S2', 'Home', 'Default']]);
  assert.deepEqual(manifest.spaces.map(space => space.expected), [
    { pinnedTabs: 2, todayTabs: 1, favoriteTabs: 0, folders: 1 },
    { pinnedTabs: 0, todayTabs: 0, favoriteTabs: 1, folders: 1 },
  ]);
  assert.equal(sum(manifest.spaces, 'pinnedTabs'), exported.counts.pinnedTabs);
  assert.equal(sum(manifest.spaces, 'todayTabs'), exported.counts.unpinnedTabs);
  assert.equal(sum(manifest.spaces, 'folders'), exported.counts.folders);
  // Each profile appears in exactly one fixture space, so per-space favorites add up to the exporter count.
  assert.equal(sum(manifest.spaces, 'favoriteTabs'), exported.counts.favoriteTabs);
  assert.deepEqual(manifest.archive, { count: archive.count, file: 'arc-archive.html' });
  assert.equal(manifest.archive.count, 2);
  assert.deepEqual(manifest.totals, { ...exported.counts, archived: 2 });
});

test('one bookmarks file per space holds only that space; the archive is written to one file only', () => {
  const exported = exportSidebar(fixture());
  const archive = exportArchive(archiveFixture());
  withOutDir(dir => {
    const manifest = writeExport(dir, exported, archive);
    const read = name => readFileSync(path.join(dir, name), 'utf8');
    assert.deepEqual(manifest.spaces.map(space => space.file), ['arc-space-S1.html', 'arc-space-S2.html']);
    assert.deepEqual(readdirSync(dir).sort(), ['arc-archive.html', 'arc-archive.json', 'arc-bookmarks.html', 'arc-sidebar.json', 'arc-space-S1.html', 'arc-space-S2.html', 'migration-manifest.json']);
    const links = html => [...html.matchAll(/<A HREF="([^"]*)"/g)].map(match => match[1]);
    const folders = html => (html.match(/<H3>[^<]*<\/H3>/g) ?? []).length;

    const work = read('arc-space-S1.html');
    assert.match(work, /<H3>Work<\/H3>[\s\S]*<H3>Pinned<\/H3>[\s\S]*<H3>Docs<\/H3>[\s\S]*A docs[\s\S]*<H3>Today<\/H3>[\s\S]*C today/);
    assert.doesNotMatch(work, /<H3>Home<\/H3>|<H3>Favorites<\/H3>|<H3>Archive<\/H3>|Pull Requests/);
    assert.deepEqual(links(work), ['https://a.example/docs', 'https://b.example/', 'https://c.example/today']);

    const home = read('arc-space-S2.html');
    assert.match(home, /<H3>Home<\/H3>[\s\S]*<H3>Favorites<\/H3>[\s\S]*Fav[\s\S]*<H3>Pinned<\/H3>[\s\S]*<H3>Pull Requests<\/H3>/);
    assert.doesNotMatch(home, /<H3>Work<\/H3>|<H3>Today<\/H3>|<H3>Archive<\/H3>|Docs/);
    assert.deepEqual(links(home), ['https://fav.example/']);

    // Each space file holds exactly the tabs its manifest entry expects.
    for (const space of manifest.spaces) {
      const html = read(space.file);
      assert.equal(links(html).length, space.expected.pinnedTabs + space.expected.todayTabs + space.expected.favoriteTabs);
      // Space, Pinned, optional Favorites and Today headings plus the folders.
      assert.equal(folders(html), 2 + (space.expected.favoriteTabs ? 1 : 0) + (space.expected.todayTabs ? 1 : 0) + space.expected.folders);
    }

    const archiveHtml = read('arc-archive.html');
    assert.deepEqual(links(archiveHtml), ['https://old.example/', 'https://gone.example/']);
    assert.doesNotMatch(archiveHtml, /<H3>Work<\/H3>|<H3>Home<\/H3>/);
    const archiveHolders = readdirSync(dir).filter(name => name.startsWith('arc-space-') || name === 'arc-archive.html').filter(name => read(name).includes('https://old.example/'));
    assert.deepEqual(archiveHolders, ['arc-archive.html']);
  });
});

test('space ids cannot escape the output directory and colliding file names are refused', () => {
  const exported = exportSidebar(fixture());
  exported.spaces[0].id = '../evil';
  assert.equal(migrationManifest(exported, null).spaces[0].file, 'arc-space-.._evil.html');
  exported.spaces[1].id = '.._evil';
  assert.throws(() => migrationManifest(exported, null), /same bookmarks file/);
});
