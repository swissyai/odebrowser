using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Sets the app-wide behavior preferences. The persistent workspace keeps
/// them on this device; they never sync. The translation rules keep to the
/// rule set's own limits, the palette names each kind of result once, and
/// the sites without previews are spelled as sites.
public sealed record SetAppPreferences(Guid WorkspaceId, AppPreferences Preferences) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        var preferences = Preferences with {
            TranslationRules = AutomaticTranslationRules.Restore(Preferences.TranslationRules).Rules,
            Palette = Preferences.Palette.Restored(),
            TabPreviews = Preferences.TabPreviews.Restored(),
            Focus = Preferences.Focus?.Restored()
        };
        return workspace.Preferred(turn.Basis, preferences);
    }

    #endregion
}
