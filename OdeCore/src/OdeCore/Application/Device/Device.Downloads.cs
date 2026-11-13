using OdeCore.Contracts;

namespace OdeCore.Application;

/// The ended downloads the device store keeps across launches: those of the
/// persistent session's Spaces that no engine keeps in a list of its own. A
/// private window's downloads, and any other Space's, are never kept.
internal sealed partial class Device {
    #region Variables

    /// The most ended downloads the store keeps, newest first.
    public const int MaximumKeptDownloads = 2_000;

    private IReadOnlyList<DownloadState> keptDownloads = [];

    /// The ended downloads the store keeps, newest first.
    internal IReadOnlyList<DownloadState> KeptDownloads {
        get {
            lock (gate) return keptDownloads;
        }
    }

    #endregion

    #region Actions - Downloads

    /// Keeps the ended records among `downloads`, newest first, whose profile
    /// is one of `profiles` and that `keepsItself` leaves to Ode, and saves
    /// them when they changed.
    internal void KeepDownloads(IEnumerable<DownloadState> downloads, IReadOnlySet<Guid> profiles, Func<Guid, bool> keepsItself) {
        ArgumentNullException.ThrowIfNull(downloads);
        ArgumentNullException.ThrowIfNull(profiles);
        ArgumentNullException.ThrowIfNull(keepsItself);
        IReadOnlyList<DownloadState> kept = [.. downloads
            .Where(download => !download.Phase.IsLive && !download.Phase.AwaitsDecision && profiles.Contains(download.ProfileId)
                && !keepsItself(download.Id))
            .Take(MaximumKeptDownloads)
            .Select(download => download with {
                Telemetry = new(download.Telemetry.BytesReceived, download.Telemetry.TotalBytes, null, null, false),
                Risk = null, IsAcknowledged = true, CanPause = false, CanResume = false
            })];
        lock (gate) {
            if (kept.SequenceEqual(keptDownloads)) return;
            keptDownloads = kept;
            storage?.EnqueueDevice(Records());
        }
    }

    #endregion
}
