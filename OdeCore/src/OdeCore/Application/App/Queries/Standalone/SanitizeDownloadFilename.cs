using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// The name a download suggested as `Suggested` is saved and shown under, by
/// the core's one rule (`DownloadFilename.Safe`). It reads no state, so the
/// platform asks it for a file's staging name, destination and type facts
/// before the download has a record.
public sealed record SanitizeDownloadFilename(string Suggested) : StandaloneQuery<SanitizedDownloadFilename> {
    #region Actions - Answering

    internal override SanitizedDownloadFilename Answer(StandaloneContext context) =>
        new(DownloadFilename.Safe(Suggested));

    #endregion
}
