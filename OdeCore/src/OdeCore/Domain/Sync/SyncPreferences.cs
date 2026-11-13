using OdeCore.Contracts;

namespace OdeCore.Domain;

public readonly record struct SyncPreferences(bool SavedStructure, bool CurrentTabs, bool HistoryAndArchive) {
    #region Actions - Sync

    public bool Includes(TabPlacement placement) => placement.IsDurable ? SavedStructure : CurrentTabs;

    #endregion
}
