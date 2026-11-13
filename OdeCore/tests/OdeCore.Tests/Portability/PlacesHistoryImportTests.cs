using System.Text;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// Bringing what other browsers keep in their own databases: the history a
/// Chromium profile keeps beside its tabs, and the bookmarks and history
/// Firefox and Zen keep in `places.sqlite`, each read from a copy that is
/// removed afterwards.
public sealed partial class BrowserContractsTests {
    private static readonly DateTimeOffset UnixEpoch = DateTimeOffset.UnixEpoch;

    /// `json` as Mozilla's LZ4 file, one block of literals.
    private static byte[] MozillaLz4(string json) {
        byte[] raw = Encoding.UTF8.GetBytes(json);
        List<byte> block = [(byte)(Math.Min(raw.Length, 15) << 4)];
        if (raw.Length >= 15) {
            int rest = raw.Length - 15;
            for (; rest >= 255; rest -= 255) block.Add(255);
            block.Add((byte)rest);
        }
        return [.. "mozLz40\0"u8, .. BitConverter.GetBytes(raw.Length), .. block, .. raw];
    }

    /// A Mozilla `places.sqlite` at `path` in `folder`, holding the places
    /// `rows` name (an address, title, visits, latest visit in seconds since
    /// 1970, and whether it is hidden) and the bookmark tree Firefox keeps:
    /// its roots, a toolbar link and a folder in it, a menu link, a tag and a
    /// saved search, which no import brings.
    private static string PlacesFile(BrowserDataFolder folder, string path,
        IEnumerable<(string Url, string Title, int Visits, long Seconds, bool Hidden)> rows) {
        string file = Path.Combine(folder.Path, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        connection.Execute("CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, "
            + "visit_count INTEGER DEFAULT 0, hidden INTEGER DEFAULT 0 NOT NULL, last_visit_date INTEGER)");
        connection.Execute("CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER DEFAULT NULL, "
            + "parent INTEGER, position INTEGER, title LONGVARCHAR, dateAdded INTEGER, guid TEXT)");
        int id = 0;
        foreach (var (url, title, visits, seconds, hidden) in rows)
            connection.Execute("INSERT INTO moz_places(id, url, title, visit_count, last_visit_date, hidden) VALUES("
                + $"{++id}, '{url}', '{title}', {visits}, {(seconds == 0 ? "NULL" : seconds * 1_000_000)}, {(hidden ? 1 : 0)})");
        connection.Execute("""
            INSERT INTO moz_bookmarks(id, type, fk, parent, position, title, dateAdded, guid) VALUES
              (1, 2, NULL, 0, 0, '', 0, 'root________'),
              (2, 2, NULL, 1, 0, 'menu', 0, 'menu________'),
              (3, 2, NULL, 1, 1, 'toolbar', 0, 'toolbar_____'),
              (4, 2, NULL, 1, 2, 'tags', 0, 'tags________'),
              (5, 2, NULL, 1, 3, 'unfiled', 0, 'unfiled_____'),
              (6, 2, NULL, 1, 4, 'mobile', 0, 'mobile______'),
              (7, 1, 1, 3, 0, 'Alpha', 1725526400000000, 'a'),
              (8, 2, NULL, 3, 1, 'Reading', 0, 'b'),
              (9, 1, 2, 8, 0, 'Beta', 0, 'c'),
              (10, 1, 3, 2, 0, 'Gamma', 0, 'd'),
              (11, 2, NULL, 4, 0, 'news', 0, 'e'),
              (12, 1, 1, 11, 0, NULL, 0, 'f'),
              (13, 1, 4, 5, 0, 'Most Visited', 0, 'g')
            """);
        return file;
    }

    /// Places as the bookmark tree above names them, and the history rows the
    /// tests read: Alpha twice-visited most recently, Gamma under two
    /// fragments, a hidden page and a saved search.
    private static readonly (string Url, string Title, int Visits, long Seconds, bool Hidden)[] Places = [
        ("https://alpha.example/", "Alpha", 2, 1_725_600_000, false),
        ("https://beta.example/", "Beta", 1, 1_725_500_000, false),
        ("https://gamma.example/#one", "Gamma", 1, 1_725_550_000, false),
        ("place:sort=8&maxResults=10", "Most Visited", 0, 0, false),
        ("https://gamma.example/#two", "Gamma two", 2, 1_725_540_000, false),
        ("https://hidden.example/", "Hidden", 4, 1_725_590_000, true)
    ];

    private static string FirefoxSessionFile(BrowserDataFolder folder, string path, params string[] urls) {
        string file = Path.Combine(folder.Path, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        string tabs = string.Join(",", urls.Select(url => $$"""{"entries":[{"url":"{{url}}","title":"Open"}],"index":1}"""));
        File.WriteAllBytes(file, MozillaLz4($$"""{"windows":[{"tabs":[{{tabs}}]}]}"""));
        return file;
    }

    private static (string Url, string Title, int Visits)[] VisitsOf(SpaceState space) =>
        [.. space.History.Select(entry => (entry.Url, entry.Title, entry.VisitCount))];

    [Fact]
    public void AChromiumProfileBringsItsHistoryWithItsTabs() {
        using var profile = new BrowserDataFolder();
        ArcHistoryFile(profile, "History", [
            ("https://older.example/", "Older", 1, 13_370_000_000, false),
            ("https://newer.example/#top", "Newer", 3, 13_370_000_100, false),
            ("https://hidden.example/", "Hidden", 9, 13_370_000_200, true)
        ]);
        string root = ImportFixture("chrome-profile", "");
        using var app = Importer();

        var spaces = app.Query(new ReadImport(ImportSource.Brave, [
            new("Default", "Personal", null, Path.Combine(root, "Default", "Sessions", "Session_1"), profile.Path)
        ])).Spaces;

        // The newest first; a hidden address is not history the person saw.
        Assert.Equal([("https://newer.example/", "Newer", 3), ("https://older.example/", "Older", 1)], VisitsOf(Assert.Single(spaces)));
    }

    [Fact]
    public void HistoryComesFromADatabaseItsBrowserHoldsLocked() {
        // A running browser holds its database open; the copy the import
        // reads must not need a lock the browser's hold refuses.
        using var profile = new BrowserDataFolder();
        ArcHistoryFile(profile, "History", [("https://open.example/", "Open", 1, 13_370_000_000, false)]);
        using var held = new FileStream(Path.Combine(profile.Path, "History"), FileMode.Open, FileAccess.ReadWrite, FileShare.None);

        Assert.Equal(["https://open.example/"], ChromiumHistory.Read(Path.Combine(profile.Path, "History")).Select(entry => entry.Address.Spelling));
    }

    [Fact]
    public void AProfileWithNothingOpenOrBookmarkedStillBringsItsHistory() {
        using var profile = new BrowserDataFolder();
        ArcHistoryFile(profile, "History", [("https://read.example/", "Read", 2, 13_370_000_000, false)]);
        using var app = Importer();

        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Brave, [new("Default", "Personal", null, null, profile.Path)])).Spaces);

        // The Space holds nothing but its Start Page, and the history.
        Assert.Equal("Personal", space.Settings.Name);
        Assert.All(space.Tabs, tab => Assert.True(tab.IsStartPage));
        Assert.Equal([("https://read.example/", "Read", 2)], VisitsOf(space));
    }

    [Fact]
    public void FirefoxBringsItsBookmarksAndHistoryFromPlaces() {
        using var firefox = new BrowserDataFolder();
        string places = PlacesFile(firefox, Path.Combine("main", "places.sqlite"), Places);
        string session = FirefoxSessionFile(firefox, Path.Combine("main", "sessionstore.jsonlz4"), "https://open.example/");
        var before = Directory.GetDirectories(Path.GetTempPath(), "ode-import-*");
        using var app = Importer();

        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Firefox, [
            new("main", "Main", places, session, Path.Combine(firefox.Path, "main"))
        ])).Spaces);

        // The roots Firefox shows become folders by the names it shows them
        // by, the toolbar first; tags and saved searches are not bookmarks.
        Assert.Equal([("Bookmarks Toolbar", null), ("Reading", "Bookmarks Toolbar"), ("Bookmarks Menu", null)], FoldersOf(space));
        Assert.Equal([
            ("Alpha", TabPlacement.Saved, "https://alpha.example/", "Bookmarks Toolbar"),
            ("Beta", TabPlacement.Saved, "https://beta.example/", "Reading"),
            ("Gamma", TabPlacement.Saved, "https://gamma.example/#one", "Bookmarks Menu"),
        ], TabsOf(space).Where(tab => tab.Placement == TabPlacement.Saved));
        Assert.Contains(TabsOf(space), tab => tab.Url == "https://open.example/" && tab.Placement == TabPlacement.Current);
        // History merges an address's fragments and leaves hidden pages and
        // saved searches out, the newest first.
        Assert.Equal([("https://alpha.example/", "Alpha", 2), ("https://gamma.example/", "Gamma", 3), ("https://beta.example/", "Beta", 1)],
            VisitsOf(space));
        Assert.Equal(before, Directory.GetDirectories(Path.GetTempPath(), "ode-import-*"));
    }

    [Fact]
    public void ZenBringsItsProfileHistoryWithItsFirstSpaceAlone() {
        using var zen = new BrowserDataFolder();
        PlacesFile(zen, Path.Combine("profile", "places.sqlite"), Places);
        string session = Path.Combine(zen.Path, "profile", "zen-sessions.jsonlz4");
        File.WriteAllBytes(session, MozillaLz4("""
            {"spaces":[{"uuid":"a","name":"Work"},{"uuid":"b","name":"Home"}],
             "tabs":[
              {"entries":[{"url":"https://work.example/","title":"Work"}],"zenWorkspace":"a"},
              {"entries":[{"url":"https://home.example/","title":"Home"}],"zenWorkspace":"b"}]}
            """));
        using var app = Importer();

        var spaces = app.Query(new ReadImport(ImportSource.Zen, [new("profile", "Zen", null, session, Path.Combine(zen.Path, "profile"))]))
            .Spaces;

        Assert.Equal(["Work", "Home"], spaces.Select(space => space.Settings.Name));
        Assert.Equal(3, spaces[0].History.Count);
        Assert.Empty(spaces[1].History);
    }

    [Fact]
    public void ADamagedPlacesDatabaseLeavesTheProfileItsOpenTabs() {
        using var firefox = new BrowserDataFolder();
        string places = firefox.Write(Path.Combine("main", "places.sqlite"), "not a database");
        string session = FirefoxSessionFile(firefox, Path.Combine("main", "sessionstore.jsonlz4"), "https://open.example/");
        using var app = Importer();

        var imported = app.Query(new ReadImport(ImportSource.Firefox, [
            new("main", "Main", places, session, Path.Combine(firefox.Path, "main"))
        ]));

        var space = Assert.Single(imported.Spaces);
        Assert.Equal(["https://open.example/"], space.Tabs.Select(tab => tab.Url));
        Assert.Empty(space.History);
        Assert.Contains(imported.LeftOut, left => left.Reason is BookmarksUnrecognized);
    }
}
