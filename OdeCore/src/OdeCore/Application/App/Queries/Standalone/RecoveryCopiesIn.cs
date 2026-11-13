using OdeCore.Application;

namespace OdeCore.Contracts;

/// The dated copies of the session file kept in `StorageDirectory`, newest
/// first, which a restore can return to. It reads the folder beside the file,
/// never the file itself, so the host asks it whether or not an app has the
/// directory open: from the browser's restore window and from the windows a
/// launch shows before the session opens.
public sealed record RecoveryCopiesIn(string StorageDirectory) : StandaloneQuery<RecoveryCopies> {
    #region Actions - Answering

    internal override RecoveryCopies Answer(StandaloneContext context) {
        if (string.IsNullOrWhiteSpace(StorageDirectory)) return new([]);
        return new(RecoveryGenerations.List(StorageDirectory));
    }

    #endregion
}
