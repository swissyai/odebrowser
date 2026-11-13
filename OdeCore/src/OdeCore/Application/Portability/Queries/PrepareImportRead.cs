using OdeCore.Application;

namespace OdeCore.Contracts;

/// Reserves a bounded import-read lifetime before detached work starts.
/// Pass the returned identity to ReadImport, and discard it on cancellation.
public sealed record PrepareImportRead : Query<Guid> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override Guid Answer(OdeApp app) => app.Portability.PrepareRead();

    #endregion
}
