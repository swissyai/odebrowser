using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void MozillaMillisecondVisitsRemainExactAfterImportAndReopen(bool zen) {
        using var directory = new StorageDirectory();
        using var profile = new BrowserDataFolder();
        const long First = 1_725_626_400_000_000, Second = First + 1_000;
        PlacesFile(profile, "places.sqlite", [("https://milliseconds.example/", "Exact", 2, First / 1_000_000, false)]);
        using (var database = SqliteConnection.Open(Path.Combine(profile.Path, "places.sqlite"), Sqlite.OpenReadWrite)) {
            database.Execute($"UPDATE moz_places SET last_visit_date={Second}");
            database.Execute("CREATE TABLE moz_historyvisits(place_id INTEGER, visit_date INTEGER, visit_type INTEGER)");
            database.Execute($"INSERT INTO moz_historyvisits VALUES(1,{First},1),(1,{Second},1)");
        }
        string? session = null;
        if (zen) {
            session = Path.Combine(profile.Path, "zen-sessions.jsonlz4");
            File.WriteAllBytes(session, MozillaLz4("""
                {"spaces":[{"uuid":"exact","name":"Exact"}],"tabs":[
                  {"entries":[{"url":"https://open.example/","title":"Open"}],"zenWorkspace":"exact"}]}
                """));
        }
        Guid imported;
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory, new TestClock(DateTimeOffset.FromUnixTimeMilliseconds(Second / 1_000)));
        using (app) {
            var read = app.Query(new ReadImport(zen ? ImportSource.Zen : ImportSource.Firefox,
                [new("Exact", "Exact", null, session, profile.Path)]));
            Assert.Empty(read.LeftOut);
            imported = Assert.Single(read.Spaces).Id;
            app.Send(new ImportSpaces(workspace, window, read.Spaces));
            app.History!.Flush();
        }
        using var reopened = OpenHistory(directory);
        List<HistoryVisits> kept = [];
        reopened.EachWithVisits(imported, kept.Add);
        var place = Assert.Single(kept);
        Assert.Equal("https://milliseconds.example/", place.Place.Url);
        Assert.Equal(new[] { First, Second }.Select(microseconds => DateTimeOffset.UnixEpoch.AddTicks(microseconds * TimeSpan.TicksPerMicrosecond)),
            place.Visits);
        Assert.Equal(2, place.Place.VisitCount);
    }

    [Fact]
    public void FullyOmittedProfileDisclosesEveryHistoryProblem() {
        using var directory = new StorageDirectory();
        using var omitted = new BrowserDataFolder();
        using var successful = new BrowserDataFolder();
        ChromiumHistoryFile(omitted, [("ftp://unsupported.example/", "Unsupported", 13_370_100_000)], []);
        using (var database = SqliteConnection.Open(Path.Combine(omitted.Path, "History"), Sqlite.OpenReadWrite))
            database.Execute("DROP TABLE visits");
        string bookmarks = successful.Write("Bookmarks", """
            {"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[
              {"type":"url","name":"Kept bookmark","url":"https://kept.example/"}]}}}
            """);
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory);
        using (app) {
            var a = new ImportProfile("A", "A", null, null, omitted.Path);
            var b = new ImportProfile("B", "B", bookmarks, null, successful.Path);
            var read = app.Query(new ReadImport(ImportSource.Chrome, [a, b]));
            var kept = Assert.Single(read.Spaces);
            Assert.Equal("B", kept.Settings.Name);
            Assert.Equal("https://kept.example/", Assert.Single(kept.Tabs).Url);
            app.Send(new ImportSpaces(workspace, window, read.Spaces));
            Assert.Contains(app.Workspace(workspace).Current.Spaces, space => space.Id == kept.Id);
            Assert.IsType<HistoryAddressesUnsupported>(Assert.Throws<Rejected>(() =>
                app.Query(new ReadImport(ImportSource.Chrome, [a]))).Rejection);
            Assert.IsType<BookmarksHaveNoLinks>(Assert.Throws<Rejected>(() =>
                app.Query(new ReadImport(ImportSource.Chrome, [new("Empty", "Empty", null, null, successful.Path)]))).Rejection);
            Assert.Equal(2, read.LeftOut.Count);
            Assert.All(read.LeftOut, omission => Assert.Equal("A", omission.Name));
            Assert.Single(read.LeftOut, omission => omission.Reason is HistoryReadFailed);
            Assert.Equal(1, Assert.IsType<HistoryAddressesUnsupported>(Assert.Single(read.LeftOut,
                omission => omission.Reason is HistoryAddressesUnsupported).Reason).Count);
        }
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void RealHistoryCapacityOmissionsReachTheImportReview(bool addressLimit) {
        using var directory = new StorageDirectory();
        using var profile = new BrowserDataFolder();
        const long Newest = 13_370_100_000;
        var epoch = new DateTimeOffset(1601, 1, 1, 0, 0, 0, TimeSpan.Zero);
        ChromiumHistoryFile(profile, [("https://capacity.example/", "Capacity", Newest)], []);
        using (var database = SqliteConnection.Open(Path.Combine(profile.Path, "History"), Sqlite.OpenReadWrite)) {
            if (addressLimit) {
                database.Execute("DELETE FROM urls");
                database.Execute("INSERT INTO urls(url,title,visit_count,last_visit_time) WITH RECURSIVE n(i) AS "
                    + $"(SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<{ImportedHistory.MaximumAddresses + 1}) "
                    + $"SELECT 'https://capacity.example/'||i, 'Page '||i, 1, ({Newest}-i)*1000000 FROM n");
            } else {
                database.Execute($"UPDATE urls SET last_visit_time={Newest}*1000000-1000");
                database.Execute("INSERT INTO visits(url,visit_time,transition) WITH RECURSIVE n(i) AS "
                    + $"(SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<{ImportedHistory.MaximumVisits + 1}) "
                    + $"SELECT 1, {Newest}*1000000-i*1000, 1 FROM n");
            }
        }
        Guid imported;
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory, new TestClock(epoch.AddSeconds(Newest)));
        using (app) {
            var read = app.Query(new ReadImport(ImportSource.Chrome, [new("Capacity", "Capacity", null, null, profile.Path)]));
            var omission = Assert.Single(read.LeftOut);
            Assert.Equal("Capacity", omission.Name);
            if (addressLimit) {
                Assert.IsType<HistoryAddressesOverLimit>(omission.Reason);
                Assert.Equal(HistoryEntryState.MaximumEntries, Assert.Single(read.Spaces).History.Count);
            } else {
                Assert.IsType<HistoryVisitsOverLimit>(omission.Reason);
                Assert.Equal(ImportedHistory.MaximumVisits, Assert.Single(Assert.Single(read.Spaces).History).VisitCount);
            }
            imported = read.Spaces[0].Id;
            app.Send(new ImportSpaces(workspace, window, read.Spaces));
            app.History!.Flush();
            Assert.Equal(0, app.Portability.PendingReads);
        }
        using var reopened = OpenHistory(directory);
        if (addressLimit) {
            Assert.Equal(((long)ImportedHistory.MaximumAddresses, (long)ImportedHistory.MaximumAddresses), reopened.Counts(imported));
            int checkedAddresses = 0;
            reopened.EachWithVisits(imported, kept => {
                int index = int.Parse(kept.Place.Url.AsSpan("https://capacity.example/".Length), System.Globalization.CultureInfo.InvariantCulture);
                Assert.InRange(index, 1, ImportedHistory.MaximumAddresses);
                Assert.Equal(epoch.AddSeconds(Newest - index), Assert.Single(kept.Visits));
                checkedAddresses++;
            });
            Assert.Equal(ImportedHistory.MaximumAddresses, checkedAddresses);
        } else {
            Assert.Equal((1L, (long)ImportedHistory.MaximumVisits), reopened.Counts(imported));
            reopened.EachWithVisits(imported, kept => {
                Assert.Equal("https://capacity.example/", kept.Place.Url);
                Assert.Equal(Enumerable.Range(0, ImportedHistory.MaximumVisits)
                    .Select(index => epoch.AddMilliseconds(Newest * 1000 - ImportedHistory.MaximumVisits + index)), kept.Visits);
            });
        }
    }

    [Fact]
    public void PartialHistoryReadDisclosesTheErrorAndPreservesMergedRealVisitsAfterReopen() {
        using var directory = new StorageDirectory();
        using var profile = new BrowserDataFolder();
        const long Newest = 13_370_100_000;
        var epoch = new DateTimeOffset(1601, 1, 1, 0, 0, 0, TimeSpan.Zero);
        ChromiumHistoryFile(profile, [("https://partial.example/page#latest", "Latest", Newest - 1),
            ("https://partial.example/page#earlier", "Earlier", Newest - 2), ("ftp://unsupported.example/", "Unsupported", Newest)], []);
        using (var database = SqliteConnection.Open(Path.Combine(profile.Path, "History"), Sqlite.OpenReadWrite)) {
            database.Execute("DROP TABLE visits");
            // A valid SQLite view yields three real rows, then a real SQLite
            // integer-overflow read error. No result flag is manufactured.
            database.Execute("CREATE VIEW visits AS WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<4) "
                + "SELECT CASE WHEN i=2 THEN 2 ELSE 1 END AS url, "
                + $"CASE WHEN i=4 THEN abs(-9223372036854775808) ELSE ({Newest}-4+i)*1000000 END AS visit_time, 1 AS transition FROM n");
        }
        Guid imported;
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory, new TestClock(epoch.AddSeconds(Newest)));
        using (app) {
            var read = app.Query(new ReadImport(ImportSource.Chrome, [new("Partial", "Partial", null, null, profile.Path)]));
            Assert.Equal(2, read.LeftOut.Count);
            Assert.Single(read.LeftOut, item => item.Reason is HistoryReadFailed);
            Assert.Equal(1, Assert.IsType<HistoryAddressesUnsupported>(Assert.Single(read.LeftOut,
                item => item.Reason is HistoryAddressesUnsupported).Reason).Count);
            imported = Assert.Single(read.Spaces).Id;
            app.Send(new ImportSpaces(workspace, window, read.Spaces));
            app.History!.Flush();
        }
        using var reopened = OpenHistory(directory);
        List<HistoryVisits> kept = [];
        reopened.EachWithVisits(imported, kept.Add);
        var place = Assert.Single(kept);
        Assert.Equal("https://partial.example/page", place.Place.Url);
        Assert.Equal("Latest", place.Place.Title);
        Assert.Equal(3, place.Place.VisitCount);
        Assert.Equal(new[] { Newest - 3, Newest - 2, Newest - 1 }.Select(seconds => epoch.AddSeconds(seconds)), place.Visits);
    }

    [Fact]
    public void UnreadableHistoryIsReportedWithoutDiscardingTheProfilesBookmarks() {
        using var profile = new BrowserDataFolder();
        profile.Write("History", "not a SQLite database");
        var bookmarks = profile.Write("Bookmarks", """
            {"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[
              {"type":"url","name":"Kept bookmark","url":"https://kept.example/"}]}}}
            """);
        using var app = new OdeApp(new AppConfiguration(null, DevicePlatform.Desktop));
        var read = app.Query(new ReadImport(ImportSource.Chrome, [new("Broken", "Broken", bookmarks, null, profile.Path)]));
        Assert.IsType<HistoryReadFailed>(Assert.Single(read.LeftOut).Reason);
        Assert.Equal("https://kept.example/", Assert.Single(Assert.Single(read.Spaces).Tabs).Url);
        Assert.Empty(read.Spaces[0].History);
    }
}
