namespace OdeCore.Contracts;

/// A font a Boost sets a site's text in. `Family` is the CSS font stack, its
/// first choice the Mac's own face and the rest what an engine without that
/// face falls back to.
///
/// The stored session and the browser-data file spell a font as its `Name`,
/// so a name never changes. A font travels as its index in `All`, so `All` is
/// append-only.
public sealed class BoostFont {
    #region Variables

    public static readonly BoostFont System = new(name: "system", title: "System",
        family: "-apple-system, system-ui, \"Helvetica Neue\", sans-serif");
    public static readonly BoostFont Rounded = new(name: "rounded", title: "Rounded",
        family: "ui-rounded, \"SF Pro Rounded\", -apple-system, system-ui, sans-serif");
    public static readonly BoostFont Serif = new(name: "serif", title: "New York",
        family: "ui-serif, \"New York\", Charter, Georgia, serif");
    public static readonly BoostFont Monospaced = new(name: "monospaced", title: "Monospaced",
        family: "ui-monospace, \"SF Mono\", Menlo, monospace");
    public static readonly BoostFont Georgia = new(name: "georgia", title: "Georgia", family: "Georgia, serif");
    public static readonly BoostFont AvenirNext = new(name: "avenirNext", title: "Avenir Next",
        family: "\"Avenir Next\", Avenir, -apple-system, sans-serif");
    public static readonly BoostFont Charter = new(name: "charter", title: "Charter", family: "Charter, Georgia, serif");

    /// The fonts, in the order the Boost bar offers them.
    public static IReadOnlyList<BoostFont> All { get; } = [System, Rounded, Serif, Monospaced, Georgia, AvenirNext, Charter];

    public string Name { get; }

    /// What the Boost bar calls the font.
    [Localized]
    public string Title { get; }

    /// The CSS font stack the font sets text in.
    public string Family { get; }

    #endregion

    #region Constructors

    private BoostFont(string name, string title, string family) {
        Name = name;
        Title = title;
        Family = family;
    }

    #endregion

    #region Actions - Lookup

    public static BoostFont? Named(string? name) => All.FirstOrDefault(font => font.Name == name);

    #endregion
}
