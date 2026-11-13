namespace OdeCore.Contracts;

/// A narrowing of the palette to one kind of result, entered by typing its
/// `Keyword`, or one of its `Words`, and pressing Tab: it then lists every
/// match of that kind, and nothing else, until the person leaves it. A word
/// enters its scope even while the field completes an address. A scope
/// travels as its index in `All`, so `All` is append-only.
public sealed class PaletteScope {
    #region Static Variables

    public static readonly PaletteScope Tabs = new(name: "tabs", keyword: "@tabs", title: "Tabs", symbol: "square.on.square",
        source: PaletteSource.OpenTabs);
    public static readonly PaletteScope Saved = new(name: "saved", keyword: "@saved", title: "Pinned & Saved", symbol: "pin",
        source: PaletteSource.Saved);
    public static readonly PaletteScope History = new(name: "history", keyword: "@history", title: "History", symbol: "clock",
        source: PaletteSource.History);
    public static readonly PaletteScope Actions = new(name: "actions", keyword: "@actions", title: "Actions", symbol: "command",
        source: PaletteSource.Actions);
    public static readonly PaletteScope Spaces = new(name: "spaces", keyword: "@spaces", title: "Spaces", symbol: "square.stack",
        source: PaletteSource.Spaces);
    /// The written answers and the guides they come from, which "help" or
    /// "ode" and Tab enter, or "?" and a space.
    public static readonly PaletteScope Help = new(name: "help", keyword: "@help", title: "Ode Help", symbol: "questionmark.circle",
        source: PaletteSource.Answers, words: ["help", "ode"], color: new(222 / 255.0, 78 / 255.0, 75 / 255.0));

    public static IReadOnlyList<PaletteScope> All { get; } = [Tabs, Saved, History, Actions, Spaces, Help];

    #endregion

    #region Variables

    public string Name { get; }

    /// What a person types before Tab to enter the scope.
    public string Keyword { get; }

    /// What the scope's chip says.
    [Localized]
    public string Title { get; }

    /// The SF Symbol the scope's chip wears.
    public string Symbol { get; }

    /// The only kind of result the scope offers.
    public PaletteSource Source { get; }

    /// Plain words that also enter the scope with Tab, without the `@`.
    public IReadOnlyList<string> Words { get; }

    /// The color of the solid pill the scope shows as once entered, as a
    /// site does, or null for the plain chip of a kind of result.
    public BrandColor? Color { get; }

    #endregion

    #region Constructors

    private PaletteScope(string name, string keyword, string title, string symbol, PaletteSource source, IReadOnlyList<string>? words = null,
        BrandColor? color = null) {
        Name = name;
        Keyword = keyword;
        Title = title;
        Symbol = symbol;
        Source = source;
        Words = words ?? [];
        Color = color;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteScope? Named(string? name) => All.FirstOrDefault(scope => scope.Name == name);

    /// The scope whose keyword is `word`, ignoring case, or null.
    public static PaletteScope? Keyed(string word) =>
        All.FirstOrDefault(scope => string.Equals(scope.Keyword, word, StringComparison.OrdinalIgnoreCase));

    /// The scope Tab enters for `typed` under `preferences`, or null: one
    /// whose keyword it is while the person offers @ filters, or one of whose
    /// words it is, each only while the person offers the scope's kind.
    internal static PaletteScope? Offered(PalettePreferences preferences, string typed) {
        string word = typed.Trim();
        var scope = Keyed(word);
        if (scope is not null && !preferences.Offers(PaletteSource.Scopes)) scope = null;
        scope ??= All.FirstOrDefault(candidate => candidate.Words.Contains(word, StringComparer.OrdinalIgnoreCase));
        return scope is not null && preferences.Offers(scope.Source) ? scope : null;
    }

    #endregion
}
