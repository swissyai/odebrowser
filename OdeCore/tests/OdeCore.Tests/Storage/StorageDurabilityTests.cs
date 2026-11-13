using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// How the files the core keeps reach the disk on Apple storage, where a
/// plain `fsync` neither flushes the drive's cache nor orders writes.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ConnectionsThatWriteOrderCheckpointsWithAFullSync() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        WriteStoredFile(directory.File, fixture.Document["session"]!.AsObject(),
            JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid())));
        using (var app = new OdeApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var storage = app.Storage!;
            Assert.Equal("wal", storage.Pragma("journal_mode"));
            Assert.Equal("2", storage.Pragma("synchronous"));
            Assert.Equal("1", storage.Pragma("checkpoint_fullfsync"));
        }
        // A copy kept with a rollback journal syncs every commit in full.
        using var copy = SqliteConnection.Open(Path.Combine(directory.Path, "copy.sqlite"), Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        Assert.Equal("1", copy.Pragma("checkpoint_fullfsync"));
        copy.RequireFullSync();
        Assert.Equal("1", copy.Pragma("fullfsync"));
    }
}
