using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The Space's newest history entries that match, ranked by how well they
/// match and how often and recently their page was visited. One that starts
/// with the text and was used enough may lead.
internal sealed class HistoryFinder : PaletteFinder {
    #region Static Variables

    /// The newest history entries a query ranks.
    public const int Scan = 1_500;

    private static readonly PaletteSignal[] signals = [PaletteSignal.Learned, PaletteSignal.Usage, PaletteSignal.Match];

    #endregion

    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals => signals;

    protected override bool MayLead => true;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        foreach (var entry in space.History.Take(Scan)) {
            var text = PlaceText.Of(entry);
            if (context.Evidence(query, text, entry: entry) is not { } evidence) continue;
            string title = entry.Title.Length > 0 ? entry.Title : text.SpelledHost ?? entry.Url;
            var row = PaletteRow.Of(PaletteRowKind.History, title, entry.Url, subject: entry.Id, address: entry.Url);
            yield return Scored(context, source, row, evidence, text.Place, Matching(evidence));
        }
    }

    #endregion
}
