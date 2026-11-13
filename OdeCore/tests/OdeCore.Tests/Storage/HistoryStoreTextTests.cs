using System.Text;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void StoredPageTextIsSearchableOnlyInItsSpaceAndFollowsTitlesAndDeletion() {
        using var directory = new StorageDirectory();
        using var store = OpenHistory(directory);
        var (work, home) = (Guid.NewGuid(), Guid.NewGuid());
        const string Url = "https://coffee.example/guide";
        store.Visit(work, Entry(Url, "Coffee guide", Morning), Morning);
        store.Visit(home, Entry(Url, "Home guide", Morning), Morning);
        store.RememberText(work, Url, "Dissolve citric acid to descale the espresso machine.", Morning);
        store.RememberText(work, "https://unvisited.example/", "unvisited secret", Morning);
        store.Flush();
        Assert.Single(store.Matching(work, "citric acid", 10));
        Assert.Empty(store.Matching(home, "citric acid", 10));
        Assert.Empty(store.Matching(work, "unvisited secret", 10));

        store.Retitle(work, Url, "Descaling guide");
        store.Flush();
        Assert.Equal("Descaling guide", Assert.Single(store.Matching(work, "citric acid", 10)).Title);
        store.Remove(work, Url);
        store.Flush();
        Assert.Empty(store.Matching(work, "citric acid", 10));
        Assert.Single(store.Places(home, null, 10).Places);
    }

    [Fact]
    public void RemovingAVisitRangeAlsoForgetsTextCapturedInThatRange() {
        using var directory = new StorageDirectory();
        using var store = OpenHistory(directory);
        var space = Guid.NewGuid();
        const string Url = "https://read.example/";
        store.Visit(space, Entry(Url, "Reading", Morning), Morning);
        store.Visit(space, Entry(Url, "Reading", Morning), Morning.AddHours(2));
        store.RememberText(space, Url, "confidential appointment", Morning.AddHours(2));
        store.Flush();
        Assert.Single(store.Matching(space, "confidential", 10));

        store.RemoveVisits(space, Morning.AddHours(1), Morning.AddHours(3));
        store.Flush();
        Assert.Single(store.Places(space, null, 10).Places);
        Assert.Empty(store.Matching(space, "confidential", 10));
        Assert.Single(store.Matching(space, "reading", 10));
    }

    [Fact]
    public void ForgettingTextIsScopedAndOlderCapturesCannotReplaceNewerText() {
        using var directory = new StorageDirectory();
        using var store = OpenHistory(directory);
        var (work, home) = (Guid.NewGuid(), Guid.NewGuid());
        const string Url = "https://read.example/";
        foreach (var space in new[] { work, home }) {
            store.Visit(space, Entry(Url, "Reading", Morning), Morning);
            store.RememberText(space, Url, "first passage", Morning);
        }
        store.RememberText(work, Url, "current passage", Morning.AddHours(2));
        store.RememberText(work, Url, "stale passage", Morning.AddHours(1));
        store.Flush();
        Assert.Single(store.Matching(work, "current", 10));
        Assert.Empty(store.Matching(work, "stale", 10));

        store.ForgetText(work);
        store.Flush();
        Assert.Empty(store.Matching(work, "passage", 10));
        Assert.Single(store.Matching(home, "first passage", 10));
        Assert.Single(store.Matching(work, "reading", 10));
        store.RememberText(home, Url, "", Morning.AddHours(3));
        store.Flush();
        Assert.Empty(store.Matching(home, "passage", 10));
    }

    [Fact]
    public void StoredPageTextHasATwoKilobyteUtf8BudgetWithoutBrokenCharacters() {
        var capped = HistoryStore.Capped(string.Concat(Enumerable.Repeat("Zürich 🚂 東京 ", 600)));
        Assert.True(Encoding.UTF8.GetByteCount(capped) <= 2_048);
        Assert.DoesNotContain('\uFFFD', capped);
        Assert.Equal(capped, Encoding.UTF8.GetString(Encoding.UTF8.GetBytes(capped)));
    }

    [Fact]
    public void CorruptOrOversizedPageTextCannotStopTitleUpdatesOrExceedTheReadBudget() {
        using var directory = new StorageDirectory();
        List<Change> changes = [];
        using var store = OpenHistory(directory, changes);
        var space = Guid.NewGuid();
        const string Broken = "https://broken.example/";
        const string Large = "https://large.example/";
        store.Visit(space, Entry(Broken, "Original", Morning), Morning);
        store.Visit(space, Entry(Large, "Original", Morning), Morning);
        store.Flush();
        using var bytes = new MemoryStream();
        using (var compressed = new System.IO.Compression.ZLibStream(bytes, System.IO.Compression.CompressionLevel.Fastest, leaveOpen: true))
            compressed.Write(Encoding.UTF8.GetBytes(new string('a', 2_000_000) + " tailmarker"));
        using (var connection = SqliteConnection.Open(Path.Combine(directory.Path, HistoryStore.FileName), Sqlite.OpenReadWrite)) {
            using var insert = connection.Prepare("INSERT INTO page_text(place, captured_at, text) SELECT id, ?, ? FROM place WHERE url = ?");
            insert.Bind(1, Morning.ToUnixTimeMilliseconds()).Bind(2, new byte[] { 1, 2, 3 }).Bind(3, Broken).Run();
            insert.Bind(1, Morning.ToUnixTimeMilliseconds()).Bind(2, bytes.ToArray()).Bind(3, Large).Run();
        }
        store.Retitle(space, Broken, "Updated title");
        store.Retitle(space, Large, "Updated title");
        store.Flush();
        Assert.Equal(2, store.Matching(space, "updated title", 10).Count);
        Assert.Empty(store.Matching(space, "tailmarker", 10));
        Assert.Contains(changes, change => change is HistoryStorageFailed {
            Operation: HistoryStorageOperation.PageText, Reason: StorageFailure.Damaged, UnsavedWrites: 0
        });
    }

    [Fact]
    public void ExistingVisitStoresGainPageTextWithoutLosingTheirVisits() {
        using var directory = new StorageDirectory();
        var space = Guid.NewGuid();
        const string Url = "https://read.example/";
        using (var original = OpenHistory(directory)) {
            original.Visit(space, Entry(Url, "Reading", Morning), Morning);
            original.Flush();
        }
        // The original visit-store schema has no page_text table.
        using (var connection = SqliteConnection.Open(Path.Combine(directory.Path, HistoryStore.FileName), Sqlite.OpenReadWrite))
            connection.Execute("DROP TABLE page_text");
        using var reopened = OpenHistory(directory);
        reopened.RememberText(space, Url, "migration preserved", Morning);
        reopened.Flush();
        Assert.Equal((1L, 1L), reopened.Counts(space));
        Assert.Single(reopened.Matching(space, "migration preserved", 10));
    }
}
