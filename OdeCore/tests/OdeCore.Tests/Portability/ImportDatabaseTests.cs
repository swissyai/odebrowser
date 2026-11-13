using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    /// A browser copied in the middle of a write has the pages of its
    /// unfinished transaction in the database and the pages they replace in
    /// its rollback journal. The copy carries the journal, so its read-only
    /// copy refuses to read, as the app's own copy does, rather than hand out
    /// addresses the browser never committed; once the browser rolls back,
    /// the emptied journal beside the database reads as the committed history.
    [Fact]
    public void HistoryCopiedMidTransactionNeverReadsUncommittedAddresses() {
        using var profile = new BrowserDataFolder();
        const int Count = 1_000;
        ChromiumHistoryFile(profile, [.. Enumerable.Range(0, Count).Select(index =>
            ($"https://committed.example/{index}/{new string('c', 200)}", "Committed", 13_370_100_000L + index))], []);
        string path = Path.Combine(profile.Path, "History");
        List<Rejection> problems = [];
        IReadOnlyList<SessionHistoryEntry> midTransaction;
        using (var browser = SqliteConnection.Open(path, Sqlite.OpenReadWrite)) {
            browser.Execute("PRAGMA journal_mode=TRUNCATE");
            browser.Execute("PRAGMA cache_size=10");
            browser.Execute("PRAGMA cache_spill=1");
            browser.Execute("BEGIN");
            browser.Execute("UPDATE urls SET url = replace(url, 'committed', 'uncommitted'), title = 'Uncommitted'");
            // SQLite writes the journal's header only once it has spilled a
            // page of the transaction into the database itself.
            Assert.Equal(JournalHeader, File.ReadAllBytes(path + "-journal")[..JournalHeader.Length]);
            midTransaction = ChromiumHistory.Read(path, problems);
            browser.Execute("ROLLBACK");
        }

        Assert.Empty(midTransaction);
        Assert.IsType<HistoryReadFailed>(Assert.Single(problems));

        problems.Clear();
        var rolledBack = ChromiumHistory.Read(path, problems);
        Assert.Equal(0, new FileInfo(path + "-journal").Length);
        Assert.Equal(Count, rolledBack.Count);
        Assert.All(rolledBack, entry => Assert.Equal("Committed", entry.Title));
        Assert.Empty(problems);
    }

    /// The bytes that open a rollback journal SQLite has synced.
    private static readonly byte[] JournalHeader = [0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7];
}
