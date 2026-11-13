using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// Importing from Arc brings, beside each Space's sidebar, the tabs Arc
/// archived for it and its profile's history.
public sealed partial class BrowserContractsTests {
    /// When the Arc test histories were last visited, in seconds since 1601.
    private const long ArcVisitedSeconds = 13_400_000_000;

    private static readonly DateTimeOffset ChromiumEpoch = new(1601, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset ReferenceEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    /// An Arc sidebar holding a Space for each of `spaces`, each with one open
    /// tab at `https://<id>.example/`, on Arc's first profile or the profile
    /// in the folder it names.
    private static string ArcSidebarWith(params (string Id, string Title, string? Profile)[] spaces) {
        var items = new JsonArray();
        var records = new JsonArray();
        foreach (var (id, title, profile) in spaces) {
            items.Add((JsonNode)$"{id}-root");
            items.Add(new JsonObject {
                ["id"] = $"{id}-root",
                ["childrenIds"] = new JsonArray($"{id}-tab"),
                ["data"] = new JsonObject { ["itemContainer"] = new JsonObject() }
            });
            items.Add((JsonNode)$"{id}-tab");
            items.Add(new JsonObject {
                ["id"] = $"{id}-tab",
                ["data"] = new JsonObject {
                    ["tab"] = new JsonObject { ["savedTitle"] = $"{title} Tab", ["savedURL"] = $"https://{id}.example/", ["timeLastActiveAt"] = 812486952 }
                }
            });
            records.Add((JsonNode)id);
            records.Add(new JsonObject {
                ["id"] = id,
                ["title"] = title,
                ["containerIDs"] = new JsonArray("unpinned", $"{id}-root"),
                ["profile"] = profile is null ? new JsonObject { ["default"] = true }
                    : new JsonObject { ["custom"] = new JsonObject { ["_0"] = new JsonObject { ["machineID"] = "m", ["directoryBasename"] = profile } } }
            });
        }
        var container = new JsonObject { ["items"] = items, ["spaces"] = records };
        return new JsonObject { ["sidebar"] = new JsonObject { ["containers"] = new JsonArray(container) } }.ToJsonString();
    }

    /// An item of Arc's archive: a tab showing `url`, archived `archivedAt`
    /// seconds after 2001 from the Space `space`, titled `title` where it saved
    /// one and `itemTitle` on the sidebar item.
    private static JsonObject ArcArchived(string id, string url, string? title, double archivedAt, string space, string? itemTitle = null) {
        var tab = new JsonObject { ["savedURL"] = url };
        if (title is not null) tab["savedTitle"] = title;
        var sidebarItem = new JsonObject { ["id"] = id, ["data"] = new JsonObject { ["tab"] = tab } };
        if (itemTitle is not null) sidebarItem["title"] = itemTitle;
        return new JsonObject {
            ["id"] = id,
            ["archivedAt"] = archivedAt,
            ["source"] = new JsonObject { ["space"] = new JsonObject { ["_0"] = space } },
            ["sidebarItem"] = sidebarItem
        };
    }

    /// Arc's archive, its items listed each after its identity.
    private static string ArcArchiveOf(IEnumerable<JsonObject> archived) {
        var items = new JsonArray();
        foreach (var item in archived) {
            items.Add((JsonNode)item["id"]!.GetValue<string>());
            items.Add(item);
        }
        return new JsonObject { ["items"] = items, ["version"] = 1 }.ToJsonString();
    }

    /// A Chromium `History` database at `path` in the folder, holding `rows`
    /// of its `urls` table: an address, title, visit count, latest visit in
    /// seconds since 1601, and whether it is hidden. `extra` runs after.
    private static void ArcHistoryFile(BrowserDataFolder folder, string path,
        IEnumerable<(string Url, string Title, int Visits, long Seconds, bool Hidden)> rows, string extra = "") {
        string file = Path.Combine(folder.Path, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        connection.Execute("CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, "
            + "visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL, "
            + "hidden INTEGER DEFAULT 0 NOT NULL)");
        foreach (var (url, title, visits, seconds, hidden) in rows)
            connection.Execute("INSERT INTO urls(url, title, visit_count, last_visit_time, hidden) VALUES("
                + $"'{url.Replace("'", "''", StringComparison.Ordinal)}', '{title.Replace("'", "''", StringComparison.Ordinal)}', "
                + $"{visits}, {seconds * 1_000_000}, {(hidden ? 1 : 0)})");
        if (extra.Length > 0) connection.Execute(extra);
    }

    /// An Arc folder whose sidebar holds "Work", on Arc's first profile, and
    /// "Home", on its profile in `Profile 1`, with an archive and a history
    /// for each.
    private static string ArcFolderWithPast(BrowserDataFolder arc) {
        string sidebar = arc.Write("StorableSidebar.json", ArcSidebarWith(("work", "Work", null), ("home", "Home", "Profile 1")));
        arc.Write("StorableArchiveItems.json", ArcArchiveOf([
            ArcArchived("a1", "https://old-work.example/", "Old Work", 800_000_000, "work"),
            ArcArchived("a2", "https://older-work.example/", title: null, 700_000_000, "work", itemTitle: "Older Work"),
            ArcArchived("h1", "https://old-home.example/", "Old Home", 750_000_000, "home"),
            ArcArchived("u1", "https://gone.example/", "Gone Space", 760_000_000, "gone"),
            ArcArchived("f1", "file:///tmp/notes.txt", "Notes", 780_000_000, "work")
        ]));
        ArcHistoryFile(arc, Path.Combine("User Data", "Default", "History"), [
            ("https://mail.example/", "Mail", 2, ArcVisitedSeconds + 3_600, false),
            ("https://news.example/", "News", 5, ArcVisitedSeconds + 10_800, false),
            ("https://hidden.example/", "Hidden", 9, ArcVisitedSeconds + 20_000, true),
            ("chrome://settings/", "Settings", 4, ArcVisitedSeconds + 30_000, false),
            ("https://docs.example/", "", 1, ArcVisitedSeconds + 7_200, false)
        ]);
        ArcHistoryFile(arc, Path.Combine("User Data", "Profile 1", "History"), [
            ("https://home-site.example/page", "Home Site", 3, ArcVisitedSeconds, false)
        ]);
        return sidebar;
    }

    private static ImportedSpaces ImportArc(string sidebar, string folder) {
        using var app = Importer();
        return app.Query(new ReadImport(ImportSource.Arc, [new("arc", "Arc", null, sidebar, Path.Combine(folder, "User Data", "Default"))]));
    }

    private static (string Title, string? Url, DateTimeOffset ArchivedAt, ArchiveReason Reason, TabPlacement Placement)[] ArchiveOf(
        SpaceState space) =>
        [.. space.ArchivedTabs.Select(archived => (archived.Tab.Title, archived.Tab.Url, archived.ArchivedAt, archived.Reason,
            archived.Tab.Placement))];

    private static (string Url, string Title, int Visits, DateTimeOffset First, DateTimeOffset Last)[] HistoryOf(SpaceState space) =>
        [.. space.History.Select(entry => (entry.Url, entry.Title, entry.VisitCount, entry.FirstVisitedAt, entry.LastVisitedAt))];

    private static string[] ArcHistoryCopies() =>
        Directory.GetDirectories(Path.GetTempPath(), "ode-import-*");

    [Fact]
    public void ArcArchivedTabsComeOnTheSpaceTheyCameFromDatedWhenArcArchivedThem() {
        using var arc = new BrowserDataFolder();
        var spaces = ImportArc(ArcFolderWithPast(arc), arc.Path).Spaces;

        Assert.Equal(["Work", "Home"], spaces.Select(space => space.Settings.Name));
        // Oldest first, as an archive lists them; the tab of a Space the
        // import does not bring joins the first, and a file is left out.
        Assert.Equal([
            ("Older Work", "https://older-work.example/", ReferenceEpoch.AddSeconds(700_000_000), ArchiveReason.Closed, TabPlacement.Current),
            ("Gone Space", "https://gone.example/", ReferenceEpoch.AddSeconds(760_000_000), ArchiveReason.Closed, TabPlacement.Current),
            ("Old Work", "https://old-work.example/", ReferenceEpoch.AddSeconds(800_000_000), ArchiveReason.Closed, TabPlacement.Current)
        ], ArchiveOf(spaces[0]));
        Assert.Equal([
            ("Old Home", "https://old-home.example/", ReferenceEpoch.AddSeconds(750_000_000), ArchiveReason.Closed, TabPlacement.Current)
        ], ArchiveOf(spaces[1]));
    }

    [Fact]
    public void ArcHistoryComesFromEachSpacesProfileNewestFirstAndOnlyItsWebPages() {
        using var arc = new BrowserDataFolder();
        var before = ArcHistoryCopies();
        var spaces = ImportArc(ArcFolderWithPast(arc), arc.Path).Spaces;

        Assert.Equal([
            ("https://news.example/", "News", 5, ChromiumEpoch.AddSeconds(ArcVisitedSeconds + 10_800),
                ChromiumEpoch.AddSeconds(ArcVisitedSeconds + 10_800)),
            ("https://docs.example/", "docs.example", 1, ChromiumEpoch.AddSeconds(ArcVisitedSeconds + 7_200),
                ChromiumEpoch.AddSeconds(ArcVisitedSeconds + 7_200)),
            ("https://mail.example/", "Mail", 2, ChromiumEpoch.AddSeconds(ArcVisitedSeconds + 3_600),
                ChromiumEpoch.AddSeconds(ArcVisitedSeconds + 3_600))
        ], HistoryOf(spaces[0]));
        Assert.Equal([
            ("https://home-site.example/page", "Home Site", 3, ChromiumEpoch.AddSeconds(ArcVisitedSeconds), ChromiumEpoch.AddSeconds(ArcVisitedSeconds))
        ], HistoryOf(spaces[1]));
        // The copies the History databases were read from are gone.
        Assert.Equal(before, ArcHistoryCopies());
    }

    [Fact]
    public void ArcSpacesSharingAProfileBringItsHistoryOnTheFirstOfThemOnly() {
        using var arc = new BrowserDataFolder();
        string sidebar = arc.Write("StorableSidebar.json",
            ArcSidebarWith(("work", "Work", null), ("home", "Home", "Profile 1"), ("side", "Side", null)));
        ArcHistoryFile(arc, Path.Combine("User Data", "Default", "History"), [("https://mail.example/", "Mail", 2, ArcVisitedSeconds, false)]);

        var spaces = ImportArc(sidebar, arc.Path).Spaces;

        Assert.Equal(["Work", "Home", "Side"], spaces.Select(space => space.Settings.Name));
        Assert.Equal(["https://mail.example/"], spaces[0].History.Select(entry => entry.Url));
        Assert.Empty(spaces[1].History);
        Assert.Empty(spaces[2].History);
    }

    [Fact]
    public void ArcSpacesKeepTheirMostRecentArchiveAndHistoryUpToWhatASpaceKeeps() {
        using var arc = new BrowserDataFolder();
        string sidebar = arc.Write("StorableSidebar.json", ArcSidebarWith(("work", "Work", null)));
        int archived = BrowserDataSpace.MaximumTabs + 2, visited = HistoryEntryState.MaximumEntries + 3;
        arc.Write("StorableArchiveItems.json", ArcArchiveOf(Enumerable.Range(1, archived)
            .Select(index => ArcArchived($"a{index}", $"https://archived.example/{index}", $"Archived {index}", 700_000_000 + index, "work"))));
        ArcHistoryFile(arc, Path.Combine("User Data", "Default", "History"), [],
            "INSERT INTO urls(url, title, visit_count, last_visit_time) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n "
            + $"WHERE i < {visited}) SELECT 'https://visited.example/' || i, 'Visited ' || i, i, ({ArcVisitedSeconds} + i) * 1000000 FROM n");

        var space = Assert.Single(ImportArc(sidebar, arc.Path).Spaces);

        Assert.Equal(BrowserDataSpace.MaximumTabs, space.ArchivedTabs.Count);
        Assert.Equal("https://archived.example/3", space.ArchivedTabs[0].Tab.Url);
        Assert.Equal($"https://archived.example/{archived}", space.ArchivedTabs[^1].Tab.Url);
        Assert.Equal(HistoryEntryState.MaximumEntries, space.History.Count);
        Assert.Equal($"https://visited.example/{visited}", space.History[0].Url);
        Assert.Equal("https://visited.example/4", space.History[^1].Url);
        Assert.Equal(ChromiumEpoch.AddSeconds(ArcVisitedSeconds + visited), space.History[0].LastVisitedAt);
    }

    [Fact]
    public void ArcWithoutAnArchiveOrHistoryOrWithUnreadableOnesStillBringsItsSidebarUnchanged() {
        using var full = new BrowserDataFolder();
        var withPast = ImportArc(ArcFolderWithPast(full), full.Path);
        using var bare = new BrowserDataFolder();
        var sidebarOnly = ImportArc(bare.Write("StorableSidebar.json", ArcSidebarWith(("work", "Work", null), ("home", "Home", "Profile 1"))),
            bare.Path);
        using var broken = new BrowserDataFolder();
        string brokenSidebar = broken.Write("StorableSidebar.json", ArcSidebarWith(("work", "Work", null), ("home", "Home", "Profile 1")));
        broken.Write("StorableArchiveItems.json", "not json");
        broken.Write(Path.Combine("User Data", "Default", "History"), "not a database");
        var unreadable = ImportArc(brokenSidebar, broken.Path);

        Assert.Empty(sidebarOnly.LeftOut);
        Assert.IsType<HistoryReadFailed>(Assert.Single(unreadable.LeftOut).Reason);
        foreach (var imported in new[] { sidebarOnly, unreadable }) {
            Assert.Equal(withPast.Spaces.Select(space => space.Settings.Name), imported.Spaces.Select(space => space.Settings.Name));
            Assert.Equal(withPast.Spaces.Select(TabsOf), imported.Spaces.Select(TabsOf));
            Assert.Equal(withPast.Spaces.Select(FoldersOf), imported.Spaces.Select(FoldersOf));
            Assert.All(imported.Spaces, space => Assert.Empty(space.ArchivedTabs));
            Assert.All(imported.Spaces, space => Assert.Empty(space.History));
        }
    }
}
