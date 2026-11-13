using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The Space's pinned and saved tabs that match, by their saved address,
/// ranked as open tabs are, with being kept in place of being open. One that
/// starts with the text may lead.
internal sealed class SavedTabFinder : PaletteFinder {
    #region Static Variables

    private static readonly PaletteSignal[] signals =
        [PaletteSignal.Learned, PaletteSignal.Recency, PaletteSignal.Usage, PaletteSignal.Kept, PaletteSignal.Match];

    #endregion

    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals => signals;

    protected override bool MayLead => true;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        var tree = new FolderTree(space.Folders);
        foreach (var tab in space.Tabs.Where(tab => tab.Placement.IsDurable)) {
            var text = PlaceText.Of(tab);
            if (context.Evidence(query, text, tab.LastActivatedAt, isKept: true) is not { } evidence) continue;
            var row = PaletteRow.Of(tab.Placement.PaletteRow, tab.DisplayTitle, Subtitle(tab, text, tree), tab: tab.Id);
            yield return Scored(context, source, row, evidence, text.Place, Matching(evidence));
        }
    }

    /// Where a saved tab lives and the site it belongs to.
    private static string Subtitle(TabState tab, PlaceText text, FolderTree tree) {
        string host = text.SpelledHost ?? "";
        if (tab.FolderId is not { } folderId) return host;
        string path = tree.PathTitle(folderId);
        return host.Length == 0 ? path : $"{path} · {host}";
    }

    #endregion
}
