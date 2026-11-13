using OdeCore.Contracts;

namespace OdeCore.Domain;

/// How one kind of result finds and scores its rows: the rows it offers for
/// typed text, the rows it offers before anything is typed, and the rows it
/// adds beside the address or search the text runs. Its signals score each
/// row it finds, in the order they name the row's reason; a kind may start
/// every row lower than another kind that matches as well, and decides whether
/// its rows may lead the palette.
internal abstract class PaletteFinder {
    #region Static Variables

    /// The finder of a kind that finds no rows itself, as search suggestions,
    /// which join after the ranked rows, or the calculator, which leads.
    public static PaletteFinder Nothing { get; } = new Quiet();

    private static readonly PaletteSignal[] signals = [PaletteSignal.Learned, PaletteSignal.Match];

    #endregion

    #region Variables

    /// The signals that score this kind's rows, in the order they name a
    /// row's reason.
    protected virtual IReadOnlyList<PaletteSignal> Signals => signals;

    /// What every row of this kind starts from.
    protected virtual int Bias => 0;

    /// Whether a row of this kind may lead the palette as its best match.
    protected virtual bool MayLead => false;

    #endregion

    #region Actions - Finding

    /// The rows the kind offers for `query`, every one when the person
    /// narrowed the palette to it and typed nothing.
    internal virtual IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) => [];

    /// The rows the kind offers before anything is typed.
    internal virtual IReadOnlyList<PaletteRow> Resting(PaletteContext context, PaletteSuggestions question) => [];

    /// The rows the kind adds beside the address or search typed text runs.
    internal virtual IEnumerable<PaletteRow> Offers(PaletteContext context, PaletteQuery query, PaletteSuggestions question) => [];

    /// The rows the kind adds before anything is typed, above every section.
    internal virtual IEnumerable<PaletteRow> RestingOffers(PaletteContext context, PaletteSuggestions question) => [];

    #endregion

    #region Actions - Scoring

    /// `row` scored by this kind's signals for `evidence`, at `place`, with
    /// the first reason a signal names, else `fallback`.
    protected PaletteCandidate Scored(PaletteContext context, PaletteSource source, PaletteRow row, PaletteEvidence evidence, string? place,
        PaletteReason? fallback) {
        int score = Bias;
        PaletteReason? reason = null;
        bool leads = false;
        foreach (var signal in Signals) {
            int points = signal.Points(evidence, context);
            score += points;
            reason ??= signal.Names(points);
            leads |= signal.Leads(points);
        }
        reason ??= fallback;
        leads &= MayLead && evidence.LeadsByText;
        var order = new PaletteOrder(evidence.Typed, evidence.Offset, evidence.TypedUses, evidence.Text?.IsHostOnly ?? false, evidence.Visits,
            evidence.LastUsed, evidence.Text?.Title ?? row.Title, evidence.Text?.Host, evidence.Text?.Core);
        return new(row with { Reason = reason }, source, score, place, leads, order);
    }

    /// The reason a place gives when no signal names one: that the text
    /// starts its title, else that it matches its address.
    protected static PaletteReason Matching(PaletteEvidence evidence) =>
        evidence.PrefixesTitle ? PaletteReason.TitleMatch : PaletteReason.AddressMatch;

    #endregion

    #region Types

    private sealed class Quiet : PaletteFinder;

    #endregion
}
