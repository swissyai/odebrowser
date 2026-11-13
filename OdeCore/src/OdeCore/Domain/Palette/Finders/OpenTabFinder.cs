using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The Space's open tabs that match, other than the one the window shows,
/// ranked by how well they match, how often their page and how recently the
/// tab was used, and whether the person prefers open tabs. One that starts
/// with the text and was used enough may lead.
internal sealed class OpenTabFinder : PaletteFinder {
    #region Static Variables

    private static readonly PaletteSignal[] signals =
        [PaletteSignal.Learned, PaletteSignal.Recency, PaletteSignal.Usage, PaletteSignal.OpenTab, PaletteSignal.Match];

    #endregion

    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals => signals;

    protected override bool MayLead => true;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        foreach (var tab in space.Tabs.Where(tab => tab.Id != context.ShownTabId && !tab.IsStartPage && !tab.Placement.IsDurable)) {
            var text = PlaceText.Of(tab);
            if (context.Evidence(query, text, tab.LastActivatedAt, isOpen: true) is not { } evidence) continue;
            var row = PaletteRow.Of(PaletteRowKind.Tab, tab.DisplayTitle, text.SpelledHost ?? tab.Url ?? "", tab: tab.Id);
            yield return Scored(context, source, row, evidence, text.Place, Matching(evidence));
        }
    }

    #endregion
}
