using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void FailedHistoryWritesDoNotProduceSuccessfulIncompleteExports() {
        using var directory = new StorageDirectory();
        var (app, engine, workspace, space, page, _) = StoredBrowsing(directory);
        using var disposal = app;
        app.History!.Flush();
        using (var connection = SqliteConnection.Open(Path.Combine(directory.Path, HistoryStore.FileName), Sqlite.OpenReadWrite))
            connection.Execute("CREATE TRIGGER refuse_history BEFORE INSERT ON place BEGIN SELECT RAISE(ABORT, 'fixture refusal'); END");
        Browse(app, engine, page, "https://failed.example/", "Failed visit");
        Assert.IsType<StorageUnreadable>(Assert.Throws<Rejected>(() => app.History.Flush()).Rejection);

        var rejected = Assert.Throws<Rejected>(() => app.Query(new ExportWorkspace(workspace, ExportFormat.History)));
        Assert.IsType<StorageUnreadable>(rejected.Rejection);
        var flushed = app.Query(new FlushHistoryStorage());
        Assert.NotNull(flushed.Failure);
        Assert.Equal(HistoryStorageOperation.Write, flushed.Failure.Operation);
        Assert.True(flushed.Failure.UnsavedWrites > 0);
        var closed = app.Query(new CloseHistoryStorage());
        Assert.NotNull(closed.Failure);
        Assert.Equal(HistoryStorageOperation.Close, closed.Failure.Operation);
        Assert.True(closed.Failure.UnsavedWrites > 0);
        app.Dispose();
    }

    [Fact]
    public void AFailedHistoryBatchRemainsAvailableAfterTheWriterRecovers() {
        using var directory = new StorageDirectory();
        using var store = OpenHistory(directory);
        var space = Guid.NewGuid();
        store.Visit(space, Entry("https://kept.example/", "Kept", Morning), Morning);
        store.Flush();
        using (var connection = SqliteConnection.Open(Path.Combine(directory.Path, HistoryStore.FileName), Sqlite.OpenReadWrite))
            connection.Execute("CREATE TRIGGER refuse_history BEFORE INSERT ON place BEGIN SELECT RAISE(ABORT, 'fixture refusal'); END");
        store.Visit(space, Entry("https://failed.example/", "Failed", Morning), Morning);
        Assert.Throws<Rejected>(() => store.Flush());
        using (var connection = SqliteConnection.Open(Path.Combine(directory.Path, HistoryStore.FileName), Sqlite.OpenReadWrite))
            connection.Execute("DROP TRIGGER refuse_history");
        store.Visit(space, Entry("https://later.example/", "Later", Morning), Morning);
        store.Flush();

        Assert.Equal((3L, 3L), store.Counts(space));
    }

    [Fact]
    public void AsyncHistoryFailuresAndFailedCloseReportExactlyWhatIsNotSaved() {
        using var directory = new StorageDirectory();
        var changes = new System.Collections.Concurrent.ConcurrentQueue<Change>();
        using var failed = new ManualResetEventSlim();
        var store = HistoryStore.Open(directory.Path, change => {
            changes.Enqueue(change);
            if (change is HistoryStorageFailed { Operation: HistoryStorageOperation.Write }) failed.Set();
        })!;
        using (var connection = SqliteConnection.Open(store.Path, Sqlite.OpenReadWrite))
            connection.Execute("CREATE TRIGGER refuse_history BEFORE INSERT ON place BEGIN SELECT RAISE(ABORT, 'fixture refusal'); END");
        store.Visit(Guid.NewGuid(), Entry("https://failed.example/", "Unsaved", Morning), Morning);
        Assert.True(failed.Wait(TimeSpan.FromSeconds(5)), "Ordinary navigation must report failure without a Flush.");
        Assert.Contains(changes, change => change is HistoryStorageFailed { Operation: HistoryStorageOperation.Write, UnsavedWrites: 1 });
        Assert.Throws<Rejected>(store.Dispose);
        Assert.Contains(changes, change => change is HistoryStorageFailed { Operation: HistoryStorageOperation.Close, UnsavedWrites: 1 });
        Assert.Throws<Rejected>(store.Flush);
        store.Dispose();
    }

    [Fact]
    public async Task HistoryFlushAndCloseRacesCannotClaimFailedQueuedWorkWasSaved() {
        using var directory = new StorageDirectory();
        using var failed = new ManualResetEventSlim();
        var store = HistoryStore.Open(directory.Path, change => {
            if (change is HistoryStorageFailed { Operation: HistoryStorageOperation.Write }) failed.Set();
        })!;
        using (var connection = SqliteConnection.Open(store.Path, Sqlite.OpenReadWrite))
            connection.Execute("CREATE TRIGGER refuse_history BEFORE INSERT ON place BEGIN SELECT RAISE(ABORT, 'fixture refusal'); END");
        store.Visit(Guid.NewGuid(), Entry("https://failed.example/", "Unsaved", Morning), Morning);
        Assert.True(failed.Wait(TimeSpan.FromSeconds(5)));
        var flush = Task.Run(() => Assert.Throws<Rejected>(store.Flush));
        var close = Task.Run(() => Assert.Throws<Rejected>(store.Dispose));
        await Task.WhenAll(flush, close).WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Throws<Rejected>(store.Flush);
        Assert.Throws<Rejected>(() => store.Places(Guid.NewGuid(), null, 10));
        store.Dispose();
    }

    [Fact]
    public void HistoryCloseRetriesTransientFailureBeforeReportingUnsavedWork() {
        using var directory = new StorageDirectory();
        using var store = OpenHistory(directory);
        var space = Guid.NewGuid();
        using (var connection = SqliteConnection.Open(store.Path, Sqlite.OpenReadWrite))
            connection.Execute("CREATE TRIGGER refuse_history BEFORE INSERT ON place BEGIN SELECT RAISE(ABORT, 'fixture refusal'); END");
        store.Visit(space, Entry("https://recovered.example/", "Retried at close", Morning), Morning);
        Assert.Throws<Rejected>(store.Flush);
        using (var connection = SqliteConnection.Open(store.Path, Sqlite.OpenReadWrite)) connection.Execute("DROP TRIGGER refuse_history");
        store.Dispose();
        store.Flush();
        using var reopened = OpenHistory(directory);
        Assert.Equal((1L, 1L), reopened.Counts(space));
    }

    [Fact]
    public void AHistoryReadFailureIsNotAnEmptySuccessfulList() {
        using var directory = new StorageDirectory();
        List<Change> changes = [];
        using var store = OpenHistory(directory, changes);
        using (var connection = SqliteConnection.Open(store.Path, Sqlite.OpenReadWrite)) connection.Execute("DROP TABLE place");
        Assert.IsType<StorageUnreadable>(Assert.Throws<Rejected>(() => store.Places(Guid.NewGuid(), null, 10)).Rejection);
        Assert.Contains(changes, change => change is HistoryStorageFailed { Operation: HistoryStorageOperation.Read });
    }

    [Fact]
    public void FailedHistoryOpenAndRecoveryMoveHaveObservableReasons() {
        using var directory = new StorageDirectory();
        List<Change> changes = [];
        string path = Path.Combine(directory.Path, HistoryStore.FileName);
        Directory.CreateDirectory(path);
        Assert.Null(HistoryStore.Open(directory.Path, changes.Add));
        Assert.Contains(changes, change => change is HistoryStorageFailed { Operation: HistoryStorageOperation.Open });
        Directory.Delete(path);
        using (var connection = SqliteConnection.Open(path, Sqlite.OpenReadWrite | Sqlite.OpenCreate))
            connection.Execute("PRAGMA user_version=999");
        if (OperatingSystem.IsWindows()) return;
        var original = File.GetUnixFileMode(directory.Path);
        try {
            File.SetUnixFileMode(directory.Path, UnixFileMode.UserRead | UnixFileMode.UserExecute);
            Assert.Null(HistoryStore.Open(directory.Path, changes.Add));
            Assert.Contains(changes, change => change is HistoryStorageFailed { Operation: HistoryStorageOperation.Recovery });
            Assert.True(File.Exists(path));
        } finally {
            File.SetUnixFileMode(directory.Path, original);
        }
    }

    [Fact]
    public void HistoryFilesAndLiveWalAreOwnerOnlyEvenInAnExistingSharedDirectory() {
        if (OperatingSystem.IsWindows()) return;
        using var directory = new StorageDirectory();
        File.SetUnixFileMode(directory.Path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute
            | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
        using var store = OpenHistory(directory);
        store.Visit(Guid.NewGuid(), Entry("https://private.example/", "Private", Morning), Morning);
        store.Flush();
        foreach (string suffix in new[] { "", "-wal", "-shm" }) {
            string file = store.Path + suffix;
            Assert.True(File.Exists(file));
            Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(file));
        }
    }

    [Fact]
    public void RepeatedFutureSchemaOpensPreserveEveryOriginalFile() {
        using var directory = new StorageDirectory();
        string path = Path.Combine(directory.Path, HistoryStore.FileName);
        foreach (var marker in new[] { "first original", "second original" }) {
            using (var connection = SqliteConnection.Open(path, Sqlite.OpenReadWrite | Sqlite.OpenCreate)) {
                connection.Execute("CREATE TABLE original_marker (value TEXT)");
                using var insert = connection.Prepare("INSERT INTO original_marker VALUES (?)");
                insert.Bind(1, marker).Run();
                connection.Execute("PRAGMA user_version=999");
            }
            using var opened = OpenHistory(directory);
        }
        var preserved = Directory.GetFiles(directory.Path, HistoryStore.FileName + ".damaged*")
            .Where(file => !file.EndsWith("-wal", StringComparison.Ordinal) && !file.EndsWith("-shm", StringComparison.Ordinal));
        List<string> markers = [];
        foreach (var file in preserved) {
            using var connection = SqliteConnection.Open(file, Sqlite.OpenReadOnly);
            using var query = connection.Prepare("SELECT value FROM original_marker");
            markers.Add(query.First(row => row.Text(0), ""));
        }
        Assert.Equal(["first original", "second original"], markers.Order());
    }
}
