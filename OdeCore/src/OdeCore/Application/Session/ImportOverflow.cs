using OdeCore.Contracts;

namespace OdeCore.Application;

/// Where an import puts each tab it adds to a Space: in the tab's own section
/// while that section has room, and past that in the section it overflows
/// to, inside the one overflow folder the import makes the first time a tab
/// spills, while the Space has room for another folder.
internal sealed class ImportOverflow {
    #region Variables

    private readonly Dictionary<TabPlacement, int> counts;
    private readonly Func<TabPlacement, Guid?> makeFolder;
    private Guid? folder;

    #endregion

    #region Constructors

    /// `placed` are the sections of the tabs the Space already holds and
    /// `folder` the overflow folder it already holds, if any. `makeFolder`
    /// adds an overflow folder in the given section to the Space and answers
    /// its identity, or answers null when the Space has no room for one.
    public ImportOverflow(IEnumerable<TabPlacement> placed, Guid? folder, Func<TabPlacement, Guid?> makeFolder) {
        counts = placed.CountBy(placement => placement).ToDictionary();
        this.folder = folder;
        this.makeFolder = makeFolder;
    }

    #endregion

    #region Actions

    /// Where the next tab of `placement` goes: its section, whether it
    /// spilled out of `placement`, and for a tab that spilled the overflow
    /// folder, or null when the Space has none.
    public (TabPlacement Placement, bool Spilled, Guid? Folder) Place(TabPlacement placement) {
        counts[placement] = counts.GetValueOrDefault(placement) + 1;
        if (placement.Fitting(counts[placement]) is var spill && spill != placement) {
            folder ??= makeFolder(spill);
            return (spill, true, folder);
        }
        return (placement, false, null);
    }

    #endregion
}
