using OdeCore.Contracts;

namespace OdeCore.Domain;

#region Types

/// What deciding the palette's best match reads for typed text: the query,
/// what it asks the palette to work out itself, the address the field
/// completes, the row the person picked before for the same text, every row
/// ranked, and whether the field may complete now.
internal sealed record PaletteLeading(PaletteQuery Query, LocalAnswer Local, AddressMatch? Completion, PaletteDestination? Habit,
    IReadOnlyList<PaletteCandidate> Ranked, bool Completes);

#endregion

/// One way a row comes to lead the palette as its best match, so Return runs
/// it. The rules are asked in order and the first that names a row leads:
/// the address the field completes, what the person picked at
/// least twice for this text, a strongly used place whose title or address
/// starts with the text, a command the text names, a written answer to what
/// the text asks, then a settings page or command whose title the text
/// spells. While the field may not complete, as after the person deleted a
/// completion, no match leads, so Return runs what they typed.
internal sealed class PaletteLeadRule {
    #region Static Variables

    /// The address the field completes, as its open tab when the person
    /// prefers open tabs and one shows it, or, when the completion is a bare
    /// host no tab shows, as the strongest tab on that host.
    public static readonly PaletteLeadRule Completion = new((context, leading) => {
        if (!leading.Completes || leading.Completion is not { } completion) return null;
        string? place = PaletteMemory.Place(completion.Opens);
        if (context.Preferences.PrefersOpenTabs
            && (leading.Ranked.FirstOrDefault(entry => entry.Place == place && entry.Row.TabId is not null) ?? OnHost(completion, leading))
                is { } open)
            return open with { Row = open.Row with { Reason = PaletteReason.Completion } };
        string host = completion.Text.Contains("://", StringComparison.Ordinal) ? completion.Text : completion.Text.TrimEnd('/');
        return new(PaletteRow.Of(PaletteRowKind.OpenAddress, $"Open {host}", completion.Opens, address: completion.Opens,
            reason: PaletteReason.Completion), PaletteSource.History, int.MaxValue, place, MayLead: true);
    });

    /// The row the person picked at least twice for exactly this text.
    public static readonly PaletteLeadRule Habit = new((context, leading) =>
        leading.Completes && leading.Habit is { } habit && leading.Ranked.FirstOrDefault(entry => context.Destination(entry.Row) == habit)
            is { } learned
            ? learned with { Row = learned.Row with { Reason = PaletteReason.Learned } }
            : null);

    /// The strongest row that may lead, once two letters are typed and the
    /// person shows a Top Hit; rows that score alike are told apart as the
    /// sections order them.
    public static readonly PaletteLeadRule StrongPlace = new((context, leading) =>
        leading.Completes && context.Preferences.ShowsTopHit && leading.Query.Text.Length >= 2
            ? leading.Ranked.Where(entry => entry.MayLead).Order(PaletteOrder.Comparer).FirstOrDefault()
            : null);

    /// The command the text names, ahead of a written answer that may only
    /// say how to run it: its whole title, enough of its title from its
    /// start, or its title in words around small ones, as "close this window"
    /// names Close Window. Of several, the one whose title the text leaves
    /// fewest words of leads, so "close window" runs Close Window rather than
    /// Close Current Tab or Window.
    public static readonly PaletteLeadRule NamedCommand = new((context, leading) => {
        if (!leading.Completes) return null;
        var asked = AnswerText.Of(leading.Query.Text);
        return leading.Ranked
            .Select(entry => (Entry: entry, Left: entry.Row.Kind != PaletteRowKind.Command ? null
                : asked.Leaves(entry.Row.Title) ?? (SpellsTitle(leading, entry) ? 0 : null)))
            .Where(named => named.Left is not null)
            .OrderBy(named => named.Left).ThenBy(named => named.Entry, PaletteOrder.Comparer)
            .Select(named => named.Entry).FirstOrDefault();
    });

    /// The written answer to what the text asks, when one card answers it
    /// clearly, the text asks no local numeric answer or time, which a card
    /// below the search answers, and the text is not the whole name of a row
    /// that leads by its name, such as a folder.
    public static readonly PaletteLeadRule Answer = new((context, leading) =>
        leading.Completes && context.Preferences.Offers(PaletteSource.Answers) && !leading.Local.AnswersOutright
            && !NamesWhole(leading) && AnswerCatalog.Shipped.Index.Lead(leading.Query.Text) is { } card
            ? new(AnswerFinder.Row(card, PaletteReason.Answers), PaletteSource.Answers, int.MaxValue, Place: null, MayLead: true)
            : null);

    /// The best ranked row whose kind leads by its title, once the text,
    /// three letters or more and not an address, spells enough of that title
    /// from its start, as "appear" does Appearance.
    public static readonly PaletteLeadRule TitledAction = new((context, leading) =>
        leading.Completes ? leading.Ranked.Where(entry => SpellsTitle(leading, entry)).Order(PaletteOrder.Comparer).FirstOrDefault() : null);

    /// The rules, in the order the palette asks them.
    public static IReadOnlyList<PaletteLeadRule> All { get; } = [Completion, Habit, StrongPlace, NamedCommand, Answer, TitledAction];

    /// The fewest letters that let a row lead by its title.
    private const int MinimumTitleLead = 3;

    #endregion

    #region Variables

    private readonly Func<PaletteContext, PaletteLeading, PaletteCandidate?> leads;

    #endregion

    #region Constructors

    private PaletteLeadRule(Func<PaletteContext, PaletteLeading, PaletteCandidate?> leads) => this.leads = leads;

    #endregion

    #region Actions - Leading

    /// The row this rule makes lead, or null when it names none.
    public PaletteCandidate? Leads(PaletteContext context, PaletteLeading leading) => leads(context, leading);

    /// The row the first rule that names one makes lead, or null when none does.
    public static PaletteCandidate? First(PaletteContext context, PaletteLeading leading) =>
        All.Select(rule => rule.Leads(context, leading)).FirstOrDefault(candidate => candidate is not null);

    /// Whether the text, three letters or more and not an address, spells
    /// enough of `entry`'s title from its start for its kind to lead by it.
    private static bool SpellsTitle(PaletteLeading leading, PaletteCandidate entry) {
        string text = leading.Query.Text;
        return text.Length >= MinimumTitleLead && !text.Contains('.', StringComparison.Ordinal)
            && !text.Contains('/', StringComparison.Ordinal) && entry.Row.Kind.TitleLeadShare is { } share
            && leading.Query.Prefixes(entry.Row.Title) && text.Length >= share * entry.Row.Title.Length;
    }

    /// Whether the text spells the whole title of a ranked row whose kind
    /// leads only by its whole title.
    private static bool NamesWhole(PaletteLeading leading) =>
        leading.Ranked.Any(entry => entry.Row.Kind.TitleLeadShare is >= 1 && leading.Query.Prefixes(entry.Row.Title)
            && leading.Query.Text.Length >= entry.Row.Title.Length);

    /// The strongest tab on the host `completion` completes to, when it
    /// completes to the host alone; null otherwise or when none is on it.
    private static PaletteCandidate? OnHost(AddressMatch completion, PaletteLeading leading) {
        if (!Uri.TryCreate(completion.Opens, UriKind.Absolute, out var opens) || opens.AbsolutePath != "/" || opens.Query.Length > 0) return null;
        string host = PaletteMemory.WithoutWww(opens.Host.ToLowerInvariant());
        return leading.Ranked.Where(entry => entry.Row.TabId is not null && entry.Order?.Host == host).Order(PaletteOrder.Comparer)
            .FirstOrDefault();
    }

    #endregion
}
