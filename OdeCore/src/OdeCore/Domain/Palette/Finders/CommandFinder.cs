using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The commands the platform offers in the palette whose title or section
/// holds what was typed, whose initials it is, or whose title it names in
/// words around small ones, as "close this window" names Close Window, once
/// two letters are typed or the person narrowed the palette to them, and the
/// few it offers before anything is typed, in the order each command says.
/// Letters scattered through a title match no command: "ode" never offers
/// Reload Page.
internal sealed class CommandFinder : PaletteFinder {
    #region Static Variables

    /// A command whose title the text names only in words, around the small
    /// ones its title does not hold, matches as though each word started a
    /// word of the title.
    private static readonly int NamedPoints = TextMatch.WordStart.Points;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (!narrowed && query.Text.Length < 2) yield break;
        var asked = AnswerText.Of(query.Text);
        foreach (var command in question.Commands.Where(command => command.Command.OffersInPalette)) {
            int? score = query.IsEmpty ? 0 : query.Score(command.Title, command.SectionTitle) ?? query.Initials(command.Title)
                ?? (asked.NamesInWords && asked.Leaves(command.Title) is not null ? NamedPoints : null);
            if (score is not { } matched) continue;
            var row = Row(command);
            yield return Scored(context, source, row, context.Matched(query, row, matched), place: null, fallback: null);
        }
    }

    internal override IReadOnlyList<PaletteRow> Resting(PaletteContext context, PaletteSuggestions question) =>
        [.. question.Commands.Where(command => command.Command.OffersInPalette && command.Command.PaletteRest is not null)
            .OrderBy(command => command.Command.PaletteRest)
            .Take(Math.Min(context.Preferences.Limit(PaletteSource.Actions), PaletteSection.Actions.RestingLimit))
            .Select(Row)];

    private static PaletteRow Row(PaletteCommand command) =>
        PaletteRow.Of(PaletteRowKind.Command, command.Title, command.SectionTitle, command.Command.Symbol, command: command.Command);

    #endregion
}
