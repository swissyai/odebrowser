using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Records whether pages in `SourceLanguage` are translated into
/// `TargetLanguage`. Region aliases of the source share one choice, so an
/// alias cannot get around turning translation off; a blank source changes
/// nothing.
public sealed record SetTranslationRule(Guid WorkspaceId, string SourceLanguage, string TargetLanguage, bool IsEnabled)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        return workspace.Preferred(turn.Basis, (turn.Basis.AppPreferences ?? AppPreferences.Default)
            .WithTranslationRule(SourceLanguage, TargetLanguage, IsEnabled));
    }

    #endregion
}
