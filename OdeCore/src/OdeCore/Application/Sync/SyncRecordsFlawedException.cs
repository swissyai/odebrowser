using OdeCore.Contracts;

namespace OdeCore.Application;

/// The records a merge or a stage would make break `Flaw`, naming `Subject`,
/// the record or Space that breaks it, when one does.
internal sealed class SyncRecordsFlawedException(SyncRecordFlaw flaw, Guid? subject) : Exception(flaw.Name) {
    #region Variables

    public SyncRecordFlaw Flaw { get; } = flaw;

    public Guid? Subject { get; } = subject;

    #endregion
}
