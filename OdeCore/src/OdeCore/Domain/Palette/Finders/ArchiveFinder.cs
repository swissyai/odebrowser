using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The Space's archived tabs that match, newest first, below a live tab that
/// matches as well. Activating one reopens it.
internal sealed class ArchiveFinder : PaletteFinder {
    #region Static Variables

    private static readonly PaletteSignal[] signals = [PaletteSignal.Match];

    #endregion

    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals => signals;

    protected override int Bias => -100;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        foreach (var archived in space.ArchivedTabs.OrderByDescending(archived => archived.ArchivedAt)) {
            var tab = archived.Tab;
            var text = PlaceText.Of(tab);
            if (context.Evidence(query, text) is not { } evidence) continue;
            var row = PaletteRow.Of(PaletteRowKind.ArchivedTab, tab.DisplayTitle, text.SpelledHost ?? "", subject: tab.Id);
            yield return Scored(context, source, row, evidence, place: null, Matching(evidence));
        }
    }

    #endregion
}
