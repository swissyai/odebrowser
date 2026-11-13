using OdeCore.Contracts;

namespace OdeCore.Application;

/// The downloads a launch brings back: once the persistent session is
/// attached, the ended downloads the device store kept for its Spaces return
/// to the ledger, and from then on the ledger's ended records of those Spaces
/// are kept there whenever they change, except those of an engine that keeps
/// its own list. Clearing, expiring or deleting a
/// record drops it from the store at the same turn.
public sealed partial class OdeApp {
    #region Variables

    private bool restoredKeptDownloads;
    private long keptDownloadsRevision = -1;

    #endregion

    #region Actions - Kept downloads

    /// Runs at the end of every turn, under the core's lock.
    private void FollowKeptDownloads(ChangeFeed changes) {
        if (storage is null || device.Persistent() is not { } persistent) return;
        var profiles = persistent.Authority.Current.Spaces.Select(space => space.ProfileId).ToHashSet();
        var ledger = downloads.Ledger;
        if (!restoredKeptDownloads) {
            restoredKeptDownloads = true;
            foreach (var kept in device.KeptDownloads.Where(download => profiles.Contains(download.ProfileId))) {
                if (ledger.Restore(kept)) downloads.Updated(ledger.Items[ledger.IndexOf(kept.Id)], changes);
            }
        }
        if (ledger.Revision == keptDownloadsRevision) return;
        keptDownloadsRevision = ledger.Revision;
        device.KeepDownloads(ledger.Items, profiles,
            downloadId => engineDownloads.Tracking(downloadId)?.Engine.Kind.KeepsDownloadList == true);
    }

    #endregion
}
