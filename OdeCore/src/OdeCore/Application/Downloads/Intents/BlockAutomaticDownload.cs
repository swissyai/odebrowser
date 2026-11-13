using OdeCore.Application;

namespace OdeCore.Contracts;

/// A live automatic download was blocked and waits for the person to retry it.
public sealed record BlockAutomaticDownload(Guid DownloadId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.BlockAutomaticDownload(DownloadId), changes);

    #endregion
}
