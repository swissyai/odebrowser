using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public void PendingImportReadsRetainEveryAddressAndExactVisitTimesAfterReopen(bool reverse, bool emptySecondHistory) {
        using var directory = new StorageDirectory();
        using var first = new BrowserDataFolder();
        using var second = new BrowserDataFolder();
        int count = HistoryEntryState.MaximumEntries + 10;
        const long Newest = 13_370_100_000;
        var epoch = new DateTimeOffset(1601, 1, 1, 0, 0, 0, TimeSpan.Zero);
        ChromiumHistoryFile(first, [.. Enumerable.Range(0, count).Select(index =>
                ($"https://first.example/{index}#fragment", $"Page {index}", Newest - index))],
            Enumerable.Range(0, count).SelectMany(index => new[] {
                (index + 1, Newest - index - 3600, 1), (index + 1, Newest - index - 600, 1), (index + 1, Newest - index, 1)
            }));
        string? secondBookmarks = null;
        if (emptySecondHistory) {
            secondBookmarks = second.Write("Bookmarks", """
                {"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[
                  {"type":"url","name":"Second","url":"https://second.example/"}]}}}
                """);
        } else {
            ChromiumHistoryFile(second, [("https://second.example/", "Second", Newest)], [(1, Newest - 60, 1), (1, Newest, 1)]);
        }
        var secondProfile = new ImportProfile("Second", "Second", secondBookmarks, null, second.Path);
        Guid firstSpace, secondSpace;
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory, new TestClock(epoch.AddSeconds(Newest)));
        using (app) {
            ImportedSpaces a, b;
            if (reverse) {
                b = app.Query(new ReadImport(ImportSource.Chrome, [secondProfile]));
                a = app.Query(new ReadImport(ImportSource.Chrome, [new("First", "First", null, null, first.Path)]));
            } else {
                a = app.Query(new ReadImport(ImportSource.Chrome, [new("First", "First", null, null, first.Path)]));
                b = app.Query(new ReadImport(ImportSource.Chrome, [secondProfile]));
            }
            firstSpace = Assert.Single(a.Spaces).Id;
            secondSpace = Assert.Single(b.Spaces).Id;
            app.Send(new ImportSpaces(workspace, window, a.Spaces));
            app.Send(new ImportSpaces(workspace, window, b.Spaces));
            app.History!.Flush();
        }
        using var reopened = OpenHistory(directory);
        List<HistoryVisits> kept = [];
        reopened.EachWithVisits(firstSpace, kept.Add);
        Assert.Equal(count, kept.Count);
        var byAddress = kept.ToDictionary(place => place.Place.Url);
        for (int index = 0; index < count; index++) {
            var place = byAddress[$"https://first.example/{index}"];
            Assert.Equal(new[] { Newest - index - 3600, Newest - index - 600, Newest - index }.Select(seconds => epoch.AddSeconds(seconds)), place.Visits);
        }
        kept.Clear();
        reopened.EachWithVisits(secondSpace, kept.Add);
        if (emptySecondHistory) Assert.Empty(kept);
        else Assert.Equal(new[] { Newest - 60, Newest }.Select(seconds => epoch.AddSeconds(seconds)), Assert.Single(kept).Visits);
    }

    [Fact]
    public async Task CanceledDetachedCompletionCannotDiscardAReplacementReadsRealVisits() {
        using var directory = new StorageDirectory();
        using var profile = new BrowserDataFolder();
        const long Newest = 13_370_100_000;
        var epoch = new DateTimeOffset(1601, 1, 1, 0, 0, 0, TimeSpan.Zero);
        ChromiumHistoryFile(profile, [("https://replacement.example/", "Replacement", Newest)],
            [(1, Newest - 3600, 1), (1, Newest - 600, 1), (1, Newest, 1)]);
        using var clock = new BlockingImportClock(epoch.AddSeconds(Newest));
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory, clock);
        Guid imported;
        using (app) {
            var canceled = app.Query(new PrepareImportRead());
            clock.BlockNext();
            var detached = Task.Run(() => Assert.Throws<Rejected>(() => app.Query(new ReadImport(ImportSource.Chrome,
                [new("Canceled", "Canceled", null, null, profile.Path)], canceled))));
            try {
                Assert.True(clock.Entered.Wait(TimeSpan.FromSeconds(10)));
                var replacement = app.Query(new ReadImport(ImportSource.Chrome,
                    [new("Replacement", "Replacement", null, null, profile.Path)]));
                imported = Assert.Single(replacement.Spaces).Id;
                Assert.True(app.Query(new DiscardImportRead(canceled)));
                // The still-running canceled read keeps its bounded admission
                // slot until it actually ends; the replacement remains owned.
                Assert.Equal(2, app.Portability.PendingReads);
                clock.Continue.Set();
                Assert.IsType<ImportReadUnavailable>((await detached.WaitAsync(TimeSpan.FromSeconds(10))).Rejection);
                Assert.Equal(1, app.Portability.PendingReads);
                app.Send(new ImportSpaces(workspace, window, replacement.Spaces));
                Assert.Equal(0, app.Portability.PendingReads);
                Assert.IsType<ImportReadUnavailable>(Assert.Throws<Rejected>(() =>
                    app.Send(new ImportSpaces(workspace, window, replacement.Spaces))).Rejection);
                Assert.Null(app.Workspace(workspace).Current.Spaces.Single(space => space.Id == imported).ImportReadId);
                app.History!.Flush();
            } finally {
                clock.Continue.Set();
                await detached.WaitAsync(TimeSpan.FromSeconds(10));
            }
        }
        using var reopened = OpenHistory(directory);
        List<HistoryVisits> kept = [];
        reopened.EachWithVisits(imported, kept.Add);
        Assert.Equal(new[] { Newest - 3600, Newest - 600, Newest }.Select(seconds => epoch.AddSeconds(seconds)), Assert.Single(kept).Visits);
    }

    [Fact]
    public void CancelRefusalAndCloseReleaseOnlyTheOwnedImportRead() {
        using var directory = new StorageDirectory();
        using var profile = new BrowserDataFolder();
        ChromiumHistoryFile(profile, [("https://pending.example/", "Pending", 13_370_100_000)], []);
        var (app, _, workspace, _, _, window) = StoredBrowsing(directory);
        using (app) {
            var pending = Enumerable.Range(0, Portability.MaximumPendingReads).Select(_ => app.Query(new ReadImport(ImportSource.Chrome,
                [new("Pending", "Pending", null, null, profile.Path), new("Other", "Other", null, null, profile.Path)]))).ToArray();
            Assert.All(pending, read => Assert.Equal(2, read.Spaces.Count));
            Assert.IsType<ImportReadLimitReached>(Assert.Throws<Rejected>(() => app.Query(new PrepareImportRead())).Rejection);
            Assert.True(app.Query(new DiscardImportRead(pending[0].Spaces[0].ImportReadId!.Value)));
            Assert.IsType<ImportReadUnavailable>(Assert.Throws<Rejected>(() =>
                app.Send(new ImportSpaces(workspace, window, pending[0].Spaces))).Rejection);
            Assert.Throws<Rejected>(() => app.Send(new ImportSpaces(Guid.NewGuid(), window, pending[1].Spaces)));
            Assert.Equal(2, app.Portability.PendingReads);
            app.Send(new ImportSpaces(workspace, window, pending[2].Spaces));
            app.History!.Flush();
            Assert.All(pending[2].Spaces, space => Assert.Equal((1L, 1L), app.History.Counts(space.Id)));
            Assert.Equal(1, app.Portability.PendingReads);
        }
        Assert.Equal(0, app.Portability.PendingReads);
        Assert.IsType<ImportReadUnavailable>(Assert.Throws<Rejected>(() => app.Query(new PrepareImportRead())).Rejection);
    }

    private sealed class BlockingImportClock(DateTimeOffset now) : IClock, IDisposable {
        #region Variables

        public ManualResetEventSlim Entered { get; } = new();
        public ManualResetEventSlim Continue { get; } = new();
        private int blocksNext;
        public DateTimeOffset Now {
            get {
                if (Interlocked.Exchange(ref blocksNext, 0) == 1) {
                    Entered.Set();
                    if (!Continue.Wait(TimeSpan.FromSeconds(10))) throw new TimeoutException("Import read was not released.");
                }
                return now;
            }
        }

        #endregion

        #region Actions - Lifetime

        public void BlockNext() => Interlocked.Exchange(ref blocksNext, 1);
        public void Dispose() {
            Entered.Dispose();
            Continue.Dispose();
        }

        #endregion
    }
}
