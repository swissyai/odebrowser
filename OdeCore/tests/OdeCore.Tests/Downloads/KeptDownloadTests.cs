using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// The ended downloads of the person's own Spaces outlast a relaunch in the
/// device store; a private window's never do, and clearing, expiring or
/// deleting a Space's data takes them out of the store too.
public sealed partial class BrowserContractsTests {
    private static readonly DateTimeOffset DownloadEpoch = new(2030, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private static IReadOnlyList<DownloadState> Relaunched(StorageDirectory directory, out Guid profile) {
        var (app, workspace, _) = DeviceApp(directory);
        using var disposal = app;
        profile = app.Workspace(workspace).Current.Spaces[0].ProfileId;
        app.Send(new AcknowledgeDownloads(profile));
        return [.. app.Downloads.Ledger.Items];
    }

    [Fact]
    public void TheEndedDownloadsOfTheSessionsSpacesComeBackAfterARelaunch() {
        using var directory = new StorageDirectory();
        Guid finished = Guid.NewGuid(), canceled = Guid.NewGuid(), running = Guid.NewGuid(), privateWindow = Guid.NewGuid();
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            var profile = app.Workspace(workspace).Current.Spaces[0].ProfileId;
            app.Send(new BeginDownload(finished, profile, "report.pdf", DownloadEpoch, false));
            app.Send(new SetDownloadDestination(finished, "file:///Users/person/Downloads/report.pdf", "report.pdf"));
            app.Send(new FinishDownload(finished, 1_234));
            app.Send(new BeginDownload(canceled, profile, "large.zip", DownloadEpoch.AddMinutes(1), false));
            app.Send(new CancelDownload(canceled, "Canceled."));
            app.Send(new BeginDownload(running, profile, "film.mov", DownloadEpoch.AddMinutes(2), false));
            // A profile no Space of the session owns, as a private window's is.
            app.Send(new BeginDownload(privateWindow, Guid.NewGuid(), "private.pdf", DownloadEpoch.AddMinutes(3), false));
            app.Send(new FinishDownload(privateWindow, 10));
        }

        var restored = Relaunched(directory, out var relaunchedProfile);

        Assert.Equal([canceled, finished], restored.Select(download => download.Id));
        Assert.All(restored, download => Assert.True(download.IsAcknowledged && download.ProfileId == relaunchedProfile));
        var file = restored[1];
        Assert.Equal((DownloadPhase.Finished, "report.pdf", "file:///Users/person/Downloads/report.pdf", 1_234L, DownloadEpoch),
            (file.Phase, file.Filename, file.Destination, file.Telemetry.BytesReceived, file.CreatedAt));
        Assert.Equal((DownloadPhase.Canceled, "Canceled."), (restored[0].Phase, restored[0].Message));
    }

    [Fact]
    public void ADownloadClearedExpiredOrDeletedWithItsSpaceIsGoneAfterARelaunch() {
        using var directory = new StorageDirectory();
        Guid cleared = Guid.NewGuid(), expired = Guid.NewGuid(), kept = Guid.NewGuid();
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            var space = app.Workspace(workspace).Current.Spaces[0];
            var own = space.ProfileId;
            var now = DateTimeOffset.UtcNow;
            foreach (var (id, age) in new[] { (cleared, 0), (expired, 3), (kept, 0) }) {
                app.Send(new BeginDownload(id, own, "file.pdf", now.AddDays(-age), false));
                app.Send(new FinishDownload(id, 1));
            }
            app.Send(new RemoveDownload(cleared));
            var preferences = space.Settings.BrowsingPreferences;
            app.Send(new SetBrowsingPreferences(workspace, space.Id, preferences.CurrentTabCleanup, preferences.ContentBlocking,
                preferences.DataRetention with { Downloads = DataRetention.OneDay }));
            app.Send(new SweepExpiredRecords(workspace));
        }

        Assert.Equal([kept], Relaunched(directory, out var profile).Select(download => download.Id));

        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            app.Send(new RemoveProfileDownloads(profile));
        }
        Assert.Empty(Relaunched(directory, out _));
    }
}
