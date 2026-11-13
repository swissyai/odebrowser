using OdeCore.Application;

namespace OdeCore.Contracts;

/// Releases one import read, never another read's data. Detached work still
/// running retains its admission slot until it ends, but cannot publish data.
public sealed record DiscardImportRead(Guid ReadId) : Query<bool> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override bool Answer(OdeApp app) => app.Portability.DiscardRead(ReadId);

    #endregion
}
