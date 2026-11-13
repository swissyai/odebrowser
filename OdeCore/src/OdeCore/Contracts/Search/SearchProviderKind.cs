namespace OdeCore.Contracts;

/// What a search provider opens: a search engine, an AI website a person asks,
/// or another website they search. The kind names its group in Settings and what
/// the palette's row for it says, and decides whether a provider of the kind
/// may be the default search. A kind travels as its index in `All`, so `All`
/// is append-only.
public sealed class SearchProviderKind {
    #region Static Variables

    public static readonly SearchProviderKind Engine = new(name: "engine", title: "Search Engines", itemTitle: "Search Engine",
        verb: "Search", symbol: "magnifyingglass", canBeDefault: true);
    public static readonly SearchProviderKind Assistant = new(name: "assistant", title: "AI Websites", itemTitle: "AI Website",
        verb: "Ask", symbol: "sparkles", canBeDefault: true,
        shortcutHelp: "Switches add website shortcuts to Command-T. For example, type chatgpt, press Tab, then enter your question. It opens on the website using your account there, not a connected account or model in Ode.");
    public static readonly SearchProviderKind Website = new(name: "website", title: "Websites", itemTitle: "Website", verb: "Search",
        symbol: "globe", canBeDefault: false);

    /// The kinds, in the order Settings groups them.
    public static IReadOnlyList<SearchProviderKind> All { get; } = [Engine, Assistant, Website];

    #endregion

    #region Variables

    public string Name { get; }

    /// What Settings calls the group of providers of this kind.
    [Localized]
    public string Title { get; }

    /// What the provider editor calls one provider of this kind.
    [Localized]
    public string ItemTitle { get; }

    /// Explains what enabling a shortcut does, where the group needs it.
    [Localized]
    public string? ShortcutHelp { get; }

    /// The SF Symbol a provider of this kind wears where it has no icon.
    public string Symbol { get; }

    /// Whether a provider of this kind may be the default search, of the
    /// device or of a Space.
    public bool CanBeDefault { get; }

    /// The word that leads what the palette's row for a provider says, as
    /// "Search" in "Search Google" or "Ask" in "Ask Claude".
    private readonly string verb;

    #endregion

    #region Constructors

    private SearchProviderKind(string name, string title, string itemTitle, string verb, string symbol, bool canBeDefault,
        string? shortcutHelp = null) {
        Name = name;
        Title = title;
        ItemTitle = itemTitle;
        ShortcutHelp = shortcutHelp;
        this.verb = verb;
        Symbol = symbol;
        CanBeDefault = canBeDefault;
    }

    #endregion

    #region Actions - Lookup

    public static SearchProviderKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    /// What the palette's row for a provider titled `provider` says.
    internal string RowTitle(string provider) => $"{verb} {provider}";

    #endregion
}
