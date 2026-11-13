using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The written answers, which rank only when the person narrowed the palette
/// to Ode Help: the cards that answer what was typed, best first, or the
/// suggested ones before anything is typed. In the open palette an answer
/// never joins the ranked rows; it leads, through its own lead rule, when the
/// text asks something one card answers.
internal sealed class AnswerFinder : PaletteFinder {
    #region Static Variables

    /// The points the best card starts from when the person narrowed the
    /// palette and typed nothing, each suggested card after it one fewer.
    private const int SuggestedScore = 1_000;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (!narrowed) return [];
        var catalog = AnswerCatalog.Shipped;
        if (query.IsEmpty)
            return catalog.Suggested.Select((card, index) =>
                new PaletteCandidate(Row(card, reason: null), source, SuggestedScore - index, Place: null, MayLead: false));
        return catalog.Index.Rank(query.Text).Select(match =>
            new PaletteCandidate(Row(match.Card, reason: null), source, (int)Math.Round(match.Score * 1_000), Place: null, MayLead: false));
    }

    /// The row that shows `card`, giving `reason` for being there.
    internal static PaletteRow Row(AnswerCard card, PaletteReason? reason) =>
        PaletteRow.Of(PaletteRowKind.Answer, card.Title, card.Steps.Count > 0 ? card.Steps[0] : "", reason: reason, answer: card);

    #endregion
}
