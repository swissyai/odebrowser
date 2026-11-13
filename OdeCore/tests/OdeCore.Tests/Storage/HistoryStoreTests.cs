using System.Text;
using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// The history kept beside the session: every visit the persistent
/// workspace's Spaces make, past the newest addresses the session keeps,
/// with what removal, retention, imports and private windows do to it.
public sealed partial class BrowserContractsTests {
    private static readonly DateTimeOffset Morning = new(2026, 10, 20, 9, 0, 0, TimeSpan.Zero);

    /// A store in `directory` that hands what it announces to `announced`.
    private static HistoryStore OpenHistory(StorageDirectory directory, List<Change>? announced = null) =>
        HistoryStore.Open(directory.Path, change => {
            lock (directory) announced?.Add(change);
        }) ?? throw new InvalidOperationException("The history store did not open.");

    private static HistoryEntryState Entry(string url, string title, DateTimeOffset at, int visits = 1) =>
        new(Guid.NewGuid(), url, title, at, at, visits);

    private static (string Url, string Title, int Visits)[] Rows(HistoryPlaces places) =>
        [.. places.Places.Select(place => (place.Url, place.Title, place.VisitCount))];

    /// A stored session with one Space, opened as a launch opens it, with a
    /// WebKit binding and one window, and the page of a Quick Window there,
    /// stamped by `clock` when one is given.
    private static (OdeApp App, Engine Engine, Guid Workspace, Guid Space, Guid Page, Guid Window) StoredBrowsing(StorageDirectory directory,
        OdeCore.Domain.IClock? clock = null) {
        var fixture = SavedSession();
        WriteStoredFile(directory.File, fixture.Document["session"]!.AsObject(), journal: null);
        var app = new OdeApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop), clock ?? new TestClock(DateTimeOffset.UtcNow),
            new TestIds());
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true),
            new RecordingEngine().Run);
        var workspace = TestWorkspaces.OpenStored(app).Workspace;
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, fixture.Space, null, window));
        app.Report(engine, new PageCreated(page));
        app.Drain();
        return (app, engine, workspace, fixture.Space, page, window);
    }

    private static HistoryPlaces Listed(OdeApp app, Guid workspace, Guid space, string text = "", int limit = 100) {
        app.History!.Flush();
        return app.Query(new HistoryList(workspace, space, text, Before: null, limit));
    }

    [Fact]
    public void TheHistoryStoreKeepsEveryVisitUntilItIsRemovedOrExpires() {
        using var directory = new StorageDirectory();
        List<Change> announced = [];
        var (work, home) = (Guid.NewGuid(), Guid.NewGuid());
        using (var store = OpenHistory(directory, announced)) {
            store.Visit(work, Entry("https://example.com/a", "First", Morning), Morning);
            store.Visit(work, Entry("https://example.com/a", "Again", Morning), Morning.AddHours(1));
            store.Visit(work, Entry("https://www.trains.example/zurich", "Zürich to Milan", Morning), Morning.AddHours(2));
            store.Visit(home, Entry("https://example.com/a", "Home's own", Morning), Morning.AddHours(3));
            store.Flush();

            // Newest first, each address once with every visit counted, and
            // each Space only its own.
            Assert.Equal([("https://www.trains.example/zurich", "Zürich to Milan", 1), ("https://example.com/a", "Again", 2)],
                Rows(store.Places(work, before: null, limit: 10)));
            Assert.Equal((2L, 3L), store.Counts(work));
            Assert.Equal(Morning, store.Places(work, null, 10).Places[1].FirstVisitedAt);
            Assert.True(store.Places(work, before: null, limit: 1).HasMore);
            Assert.Equal(["https://example.com/a"], store.Places(work, Morning.AddHours(2), 10).Places.Select(place => place.Url));

            // Words match titles and addresses, accents folded, the last word as a start.
            Assert.Equal(["https://www.trains.example/zurich"], store.Matching(work, "zurich mil", 10).Select(place => place.Url));
            Assert.Equal(["https://example.com/a"], store.Matching(work, "agai", 10).Select(place => place.Url));
            Assert.Empty(store.Matching(home, "zurich", 10));

            // Removing a stretch of time leaves a page its earlier visits;
            // one visited only then goes.
            store.RemoveVisits(work, Morning.AddMinutes(30), Morning.AddHours(3));
            store.Flush();
            Assert.Equal([("https://example.com/a", "Again", 1)], Rows(store.Places(work, null, 10)));
            Assert.Equal(Morning, store.Places(work, null, 10).Places[0].LastVisitedAt);

            // A site goes whole, with its subdomains, from that Space only.
            store.Visit(home, Entry("https://docs.example.com/b", "Docs", Morning), Morning.AddHours(4));
            store.RemoveSite(home, "www.example.com");
            store.Flush();
            Assert.Empty(store.Places(home, null, 10).Places);
            Assert.Single(store.Places(work, null, 10).Places);

            // Retention removes what is older than the Space keeps.
            store.Expire(work, Morning.AddMinutes(1));
            store.Flush();
            Assert.Empty(store.Places(work, null, 10).Places);
            Assert.Empty(store.Matching(work, "again", 10));
        }
        long[] revisions = [.. announced.OfType<StoredHistoryChanged>().Select(change => change.Revision)];
        Assert.NotEmpty(revisions);
        Assert.Equal(revisions.Order(), revisions);
    }

    [Fact]
    public void AnImportTakenInTwiceCountsNothingTwiceAndSurvivesAReopen() {
        using var directory = new StorageDirectory();
        var space = Guid.NewGuid();
        ImportedPlace[] places = [
            new("https://read.example/", "Read", Morning.AddDays(-9), Morning, 7,
                [Morning.AddDays(-9), Morning.AddDays(-2), Morning]),
            new("https://counted.example/", "Counted", Morning.AddDays(-30), Morning.AddDays(-1), 40, [])
        ];
        using (var store = OpenHistory(directory)) {
            store.Visit(space, Entry("https://read.example/", "Read here", Morning.AddHours(1)), Morning.AddHours(1));
            store.Import(space, places);
            store.Import(space, places);
            store.Flush();
        }
        using var reopened = OpenHistory(directory);
        var kept = reopened.Places(space, null, 10).Places;
        // The address visited here keeps the later title, its own visit and
        // the imported ones; one with no visit times keeps the count its
        // browser kept and its first and latest visit.
        Assert.Equal([("https://read.example/", "Read here", 7), ("https://counted.example/", "Counted", 40)],
            kept.Select(place => (place.Url, place.Title, place.VisitCount)));
        Assert.Equal(Morning.AddDays(-9), kept[0].FirstVisitedAt);
        Assert.Equal((2L, 6L), reopened.Counts(space));
        List<HistoryVisits> exported = [];
        reopened.EachWithVisits(space, exported.Add);
        Assert.Equal([Morning.AddDays(-9), Morning.AddDays(-2), Morning, Morning.AddHours(1)], exported[0].Visits);
        Assert.Equal([Morning.AddDays(-30), Morning.AddDays(-1)], exported[1].Visits);
    }

    [Fact]
    public void ThePersistentWorkspaceKeepsEveryVisitAndPrivateOrLockedBrowsingKeepsNone() {
        using var directory = new StorageDirectory();
        var clock = new TestClock(DateTimeOffset.UtcNow);
        var (app, engine, workspace, space, page, _) = StoredBrowsing(directory, clock);
        using var disposal = app;

        // What the session kept before the store comes first, once.
        Assert.Equal([("https://example.com/article", "Earlier visit", 4)], Rows(Listed(app, workspace, space)));

        foreach (var (url, title) in new[] {
            ("https://news.example/story#top", "Story"), ("https://news.example/second", "Second"),
            ("https://news.example/story", "Story again") }) {
            clock.Now = clock.Now.AddMinutes(1);
            Browse(app, engine, page, url, title);
        }
        Assert.Equal([("https://news.example/story", "Story again", 2), ("https://news.example/second", "Second", 1),
            ("https://example.com/article", "Earlier visit", 4)], Rows(Listed(app, workspace, space)));
        Assert.Equal(["https://news.example/second"], Listed(app, workspace, space, "second").Places.Select(place => place.Url));

        // A private window's pages keep nothing beside the session.
        var privateWorkspace = TestWorkspaces.Open(app, SavedSession().Document["session"]!, WorkspaceKind.Private);
        var privateWindow = Guid.NewGuid();
        app.Send(new OpenWindow(privateWindow, privateWorkspace, Saved: false, null, null, [], RestoresTabs: true));
        var privateSpace = app.Workspace(privateWorkspace).Current.Spaces[0].Id;
        var privatePage = Guid.NewGuid();
        app.Send(new OpenPage(privatePage, privateWorkspace, privateSpace, null, privateWindow));
        app.Report(engine, new PageCreated(privatePage));
        Browse(app, engine, privatePage, "https://private.example/", "Private");
        app.History!.Flush();
        Assert.Equal((0L, 0L), app.History.Counts(privateSpace));
        Assert.Empty(Listed(app, workspace, space, "private").Places);

        // A Blank Window borrows the profile, not its durable history store.
        var source = app.Workspace(workspace).Current.Spaces.Single(candidate => candidate.Id == space);
        var blank = TestWorkspaces.Opened(app.Send(new BorrowSpace(workspace, space, source.ProfileId)));
        var blankWindow = Guid.NewGuid();
        app.Send(new OpenWindow(blankWindow, blank, Saved: false, null, null, [], RestoresTabs: true));
        var blankPage = Guid.NewGuid();
        app.Send(new OpenPage(blankPage, blank, space, null, blankWindow));
        app.Report(engine, new PageCreated(blankPage));
        Browse(app, engine, blankPage, "https://blank.example/", "Blank");
        Assert.Empty(Listed(app, workspace, space, "blank").Places);

        // Removing an address removes its visits.
        app.Send(new RemoveHistoryAddress(workspace, space, "https://news.example/second#again"));
        Assert.Equal(2, Listed(app, workspace, space).Places.Count);

        // A locked Space neither shows its history nor records a visit.
        app.Send(new SetSpaceAccess(workspace, space, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Browse(app, engine, page, "https://news.example/locked", "Locked");
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => Listed(app, workspace, space)).Rejection);
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => app.Query(new ExportWorkspace(workspace, ExportFormat.History))).Rejection);
        Assert.Equal((2L, 4L), app.History.Counts(space));
    }

    [Fact]
    public void RetentionAppliesToEveryVisitKeptBesideTheSession() {
        using var directory = new StorageDirectory();
        var (app, engine, workspace, space, page, _) = StoredBrowsing(directory);
        using var disposal = app;
        Browse(app, engine, page, "https://news.example/today", "Today");
        Assert.Equal(2, Listed(app, workspace, space).Places.Count);

        // The adopted visit is months old; a Space keeping 30 days drops it.
        var preferences = app.Workspace(workspace).Current.Spaces[0].Settings.BrowsingPreferences;
        app.Send(new SetBrowsingPreferences(workspace, space, preferences.CurrentTabCleanup, preferences.ContentBlocking,
            preferences.DataRetention with { History = DataRetention.ThirtyDays }));
        Assert.Equal(["https://news.example/today"], Listed(app, workspace, space).Places.Select(place => place.Url));
        app.Send(new SweepExpiredRecords(workspace));
        Assert.Equal(["https://news.example/today"], Listed(app, workspace, space).Places.Select(place => place.Url));

        // Clearing the Space's history clears every visit kept beside it.
        app.Send(new ClearHistory(workspace, space, BrowsingDataRange.AllTime));
        Assert.Empty(Listed(app, workspace, space).Places);
    }

    /// A Chromium `History` database in `folder` holding `addresses`, each
    /// once with its title and latest visit in seconds since 1601, and the
    /// visits `visits` name by address row, with Chromium's transition.
    private static void ChromiumHistoryFile(BrowserDataFolder folder, IReadOnlyList<(string Url, string Title, long Seconds)> addresses,
        IEnumerable<(int Row, long Seconds, int Transition)> visits) {
        using var connection = SqliteConnection.Open(Path.Combine(folder.Path, "History"), Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        connection.Execute("CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, "
            + "visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL, "
            + "hidden INTEGER DEFAULT 0 NOT NULL)");
        connection.Execute("CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, "
            + "from_visit INTEGER, transition INTEGER DEFAULT 0 NOT NULL)");
        connection.InTransaction(() => {
            using var insert = connection.Prepare("INSERT INTO urls(url, title, visit_count, last_visit_time) VALUES(?,?,1,?)");
            foreach (var (url, title, seconds) in addresses) insert.Bind(1, url).Bind(2, title).Bind(3, seconds * 1_000_000).Run();
            using var visit = connection.Prepare("INSERT INTO visits(url, visit_time, transition) VALUES(?,?,?)");
            foreach (var (row, seconds, transition) in visits) visit.Bind(1, row).Bind(2, seconds * 1_000_000).Bind(3, transition).Run();
        });
    }

    /// Safari's `History.db` in `folder`: `items`, each address with its
    /// count, and `visits`, each by item, in seconds since 2001, with the
    /// title then and whether it loaded.
    private static void SafariHistoryFile(BrowserDataFolder folder, IEnumerable<(int Id, string Url, int Visits)> items,
        IEnumerable<(int Item, double Seconds, string? Title, bool Loaded)> visits) {
        using var connection = SqliteConnection.Open(Path.Combine(folder.Path, "History.db"), Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        connection.Execute("CREATE TABLE history_items (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, "
            + "domain_expansion TEXT NULL, visit_count INTEGER NOT NULL)");
        connection.Execute("CREATE TABLE history_visits (id INTEGER PRIMARY KEY AUTOINCREMENT, history_item INTEGER NOT NULL, "
            + "visit_time REAL NOT NULL, title TEXT NULL, load_successful BOOLEAN NOT NULL DEFAULT 1)");
        using var item = connection.Prepare("INSERT INTO history_items(id, url, visit_count) VALUES(?,?,?)");
        foreach (var (id, url, count) in items) item.Bind(1, id).Bind(2, url).Bind(3, count).Run();
        using var visit = connection.Prepare("INSERT INTO history_visits(history_item, visit_time, title, load_successful) VALUES(?,?,?,?)");
        foreach (var (owner, seconds, title, loaded) in visits) visit.Bind(1, owner).Bind(2, seconds).Bind(3, title).Bind(4, loaded ? 1 : 0).Run();
    }

    [Fact]
    public void AnImportBringsEveryAddressWithItsVisitsWhileTheSpaceKeepsTheNewest() {
        using var directory = new StorageDirectory();
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory);
        using var disposal = app;
        using var profile = new BrowserDataFolder();
        int count = HistoryEntryState.MaximumEntries + 10;
        const long Newest = 13_370_100_000;
        // The newest address has two visits of its own and one a frame made.
        ChromiumHistoryFile(profile, [.. Enumerable.Range(0, count).Select(index =>
                ($"https://site{index}.example/page#part", $"Page {index}", Newest - count + 1 + index))],
            [(count, Newest - 86_400, 805_306_368), (count, Newest, 1), (count, Newest - 60, 3)]);

        var read = app.Query(new ReadImport(ImportSource.Chrome, [new("Default", "Personal", null, null, profile.Path)]));
        var imported = Assert.Single(read.Spaces);
        app.Send(new ImportSpaces(workspace, window, read.Spaces));

        // The Space keeps its newest addresses; the history beside it keeps them all.
        var space = app.Workspace(workspace).Current.Spaces.Single(candidate => candidate.Id == imported.Id);
        Assert.Equal(HistoryEntryState.MaximumEntries, space.History.Count);
        var all = Listed(app, workspace, space.Id, limit: HistoryList.MaximumLimit);
        Assert.Equal(HistoryList.MaximumLimit, all.Places.Count);
        Assert.True(all.HasMore);
        var rest = app.Query(new HistoryList(workspace, space.Id, "", all.Places[^1].LastVisitedAt, HistoryList.MaximumLimit));
        Assert.Equal(count, all.Places.Count + rest.Places.Count);
        Assert.Equal(("https://site0.example/page", "Page 0"), (rest.Places[^1].Url, rest.Places[^1].Title));
        var newest = all.Places[0];
        Assert.Equal(($"https://site{count - 1}.example/page", 2), (newest.Url, newest.VisitCount));
        Assert.Equal(newest.LastVisitedAt.AddDays(-1), newest.FirstVisitedAt);
        // An older address is found by its words, past the Space's own list.
        Assert.Equal(["https://site3.example/page"], Listed(app, workspace, space.Id, "site3 example").Places.Select(place => place.Url));

        // The export writes every address, each with its visits.
        var lines = Encoding.UTF8.GetString(app.Query(new ExportWorkspace(workspace, ExportFormat.History)).Contents)
            .Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal(count + 1, lines.Length);
        var line = JsonNode.Parse(lines.First(text => text.Contains($"site{count - 1}.example", StringComparison.Ordinal)))!;
        Assert.Equal(2, line["visits"]!.AsArray().Count);
    }

    [Fact]
    public void HistoryPaginationKeepsAddressesWithTheSameVisitTime() {
        using var directory = new StorageDirectory();
        using var store = OpenHistory(directory);
        var space = Guid.NewGuid();
        foreach (var name in new[] { "alpha", "beta", "gamma" })
            store.Visit(space, Entry($"https://{name}.example/", name, Morning), Morning);
        store.Flush();

        var first = store.Places(space, null, 2);
        var second = store.Places(space, first.Places[^1].LastVisitedAt, 2, first.Places[^1].Url);
        Assert.True(first.HasMore);
        Assert.Equal(3, first.Places.Count + second.Places.Count);
    }

    [Fact]
    public void AnExportIncludesHistoryStillQueuedByAnImport() {
        using var directory = new StorageDirectory();
        var (app, _, workspace, space, _, _) = StoredBrowsing(directory);
        using var disposal = app;
        const int Count = 10_000;
        app.History!.Import(space, [.. Enumerable.Range(0, Count).Select(index =>
            new ImportedPlace($"https://queued.example/{index}", $"Page {index}", Morning, Morning, 1, [Morning]))]);

        var exported = app.Query(new ExportWorkspace(workspace, ExportFormat.History));
        Assert.Equal(Count + 1, Encoding.UTF8.GetString(exported.Contents).Split('\n', StringSplitOptions.RemoveEmptyEntries).Length);
    }

    [Fact]
    public void ImportedHistoryHonorsTheDestinationSpacesRetention() {
        using var directory = new StorageDirectory();
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory);
        using var disposal = app;
        using var profile = new BrowserDataFolder();
        ChromiumHistoryFile(profile, [("https://expired.example/", "Expired", 13_370_100_000)], []);
        var read = app.Query(new ReadImport(ImportSource.Chrome, [new("Default", "Personal", null, null, profile.Path)]));
        var imported = Assert.Single(read.Spaces);
        var preferences = imported.Settings.BrowsingPreferences;
        var retention = preferences.DataRetention with { History = DataRetention.OneDay };
        var settings = imported.Settings with { BrowsingPreferences = preferences with { DataRetention = retention } };
        imported = imported with { Settings = settings };
        app.Send(new ImportSpaces(workspace, window, [imported]));
        Assert.Empty(Listed(app, workspace, imported.Id).Places);
    }

    [Fact]
    public void AdoptingSessionHistoryIsIdempotentAndDoesNotRestoreRemovedAddresses() {
        using var directory = new StorageDirectory();
        using var device = new TestDevice(SavedSession().Document["session"]!);
        var session = device.Authority.Current;
        var space = session.Spaces[0];
        using (var store = OpenHistory(directory)) {
            store.Adopt(session.Spaces);
            store.Flush();
            Assert.Single(store.Places(space.Id, null, 10).Places);
            store.Remove(space.Id, space.History[0].Url);
            store.Flush();
        }
        using var reopened = OpenHistory(directory);
        reopened.Adopt(session.Spaces);
        reopened.Flush();
        Assert.Empty(reopened.Places(space.Id, null, 10).Places);
        Assert.Equal((0L, 0L), reopened.Counts(space.Id));
    }

    [Fact]
    public void AHistoryFileFromANewerVersionIsPreservedBeforeStartingANewStore() {
        using var directory = new StorageDirectory();
        string path = Path.Combine(directory.Path, HistoryStore.FileName);
        using (var connection = SqliteConnection.Open(path, Sqlite.OpenReadWrite | Sqlite.OpenCreate)) {
            connection.Execute("CREATE TABLE future_record (value TEXT)");
            connection.Execute("INSERT INTO future_record VALUES ('preserved')");
            connection.Execute("PRAGMA user_version=999");
        }
        using var store = OpenHistory(directory);
        Assert.Equal((0L, 0L), store.Counts(Guid.NewGuid()));
        using var preserved = SqliteConnection.Open(path + ".damaged", Sqlite.OpenReadOnly);
        Assert.Equal(999, preserved.ReadUserVersion());
        using var record = preserved.Prepare("SELECT value FROM future_record");
        Assert.Equal("preserved", record.First(row => row.Text(0), ""));
        if (!OperatingSystem.IsWindows())
            Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(path));
    }

    [Fact]
    public void SafariHistoryReadsCommittedVisitsFromACopyWhileTheSourceIsWriting() {
        using var profile = new BrowserDataFolder();
        SafariHistoryFile(profile, [(1, "https://read.example/", 1)], [(1, 800_000_000, "First", true)]);
        using var source = SqliteConnection.Open(Path.Combine(profile.Path, SafariHistory.FileName), Sqlite.OpenReadWrite);
        source.Execute("PRAGMA journal_mode=WAL");
        source.Execute("INSERT INTO history_visits(history_item, visit_time, title) VALUES (1, 800100000, 'Committed')");
        source.Execute("BEGIN IMMEDIATE");
        source.Execute("INSERT INTO history_visits(history_item, visit_time, title) VALUES (1, 800200000, 'Uncommitted')");
        try {
            var imported = Assert.Single(SafariHistory.Read(profile.Path));
            Assert.Equal("Committed", imported.Title);
            Assert.Equal(2, imported.Visits!.Count);
        } finally {
            source.Execute("ROLLBACK");
        }
    }

    [Fact]
    public void SafariAndFirefoxBringTheirVisitsToo() {
        using var safari = new BrowserDataFolder();
        // Seconds since 2001; Safari titles each visit, and one that did not load is no visit.
        SafariHistoryFile(safari, [(1, "https://read.example/a#x", 3), (2, "https://failed.example/", 1)], [
            (1, 800_000_000, "Old title", true), (1, 800_100_000, "New title", true), (1, 800_050_000, null, true),
            (2, 800_000_000, "Failed", false)]);
        using var app = Importer();

        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Safari, [new("safari", "Safari", null, null, safari.Path)])).Spaces);
        Assert.Equal([("https://read.example/a", "New title", 3)], VisitsOf(space));
        var read = Assert.Single(SafariHistory.Read(safari.Path));
        Assert.Equal([800_000_000d, 800_050_000d, 800_100_000d], read.Visits!.Select(StoredSessionCodec.Seconds));

        using var firefox = new BrowserDataFolder();
        string places = PlacesFile(firefox, Path.Combine("main", "places.sqlite"), Places);
        using (var connection = SqliteConnection.Open(places, Sqlite.OpenReadWrite)) {
            connection.Execute("CREATE TABLE moz_historyvisits(id INTEGER PRIMARY KEY, from_visit INTEGER, place_id INTEGER, "
                + "visit_date INTEGER, visit_type INTEGER)");
            connection.Execute("INSERT INTO moz_historyvisits(place_id, visit_date, visit_type) VALUES "
                + "(1, 1725500000000000, 1), (1, 1725600000000000, 2), (1, 1725550000000000, 4)");
        }
        var alpha = MozillaPlaces.History(Path.Combine(firefox.Path, "main")).First(entry => entry.Address.Spelling == "https://alpha.example/");
        Assert.Equal([1_725_500_000d, 1_725_600_000d], alpha.Visits!.Select(ImportDate.UnixSeconds));
    }
}
