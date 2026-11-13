namespace OdeCore.Contracts;

/// What activating a palette row does, which the platform performs: switch
/// to its tab, open its address, search with its provider, run its command,
/// open its settings page, show its Space, reopen its archived tab, copy its
/// answer, narrow the palette to its scope, run a written answer's action, or
/// do what a card says.
/// Each says whether
/// the palette closes once it is done and remembers the pick for what was
/// typed, and whether the keys a person holds choose where the row opens. An
/// activation travels as its index in `All`, so `All` is append-only.
public sealed class PaletteActivation {
    #region Static Variables

    public static readonly PaletteActivation SwitchesToTab = new(name: "switchesToTab", closesPalette: true, opensWhereKeysChoose: false);
    public static readonly PaletteActivation OpensAddress = new(name: "opensAddress", closesPalette: true, opensWhereKeysChoose: true);
    public static readonly PaletteActivation Searches = new(name: "searches", closesPalette: true, opensWhereKeysChoose: true);
    public static readonly PaletteActivation RunsCommand = new(name: "runsCommand", closesPalette: true, opensWhereKeysChoose: false);
    public static readonly PaletteActivation OpensSettingsPage = new(name: "opensSettingsPage", closesPalette: true,
        opensWhereKeysChoose: false);
    public static readonly PaletteActivation ShowsSpace = new(name: "showsSpace", closesPalette: true, opensWhereKeysChoose: false);
    public static readonly PaletteActivation ReopensArchivedTab = new(name: "reopensArchivedTab", closesPalette: true,
        opensWhereKeysChoose: false);
    public static readonly PaletteActivation CopiesAnswer = new(name: "copiesAnswer", closesPalette: true, opensWhereKeysChoose: false);
    public static readonly PaletteActivation EntersScope = new(name: "entersScope", closesPalette: false, opensWhereKeysChoose: false);
    /// Runs what a written answer's "Do it" names, or opens its guide when it
    /// names nothing or the person chose to read more.
    public static readonly PaletteActivation RunsAnswer = new(name: "runsAnswer", closesPalette: true, opensWhereKeysChoose: false);
    /// Does what a card's kind says Return does: copy its value, look its
    /// term up in the dictionary, or open its address where the keys choose.
    public static readonly PaletteActivation RunsCard = new(name: "runsCard", closesPalette: true, opensWhereKeysChoose: true);

    public static IReadOnlyList<PaletteActivation> All { get; } = [SwitchesToTab, OpensAddress, Searches, RunsCommand, OpensSettingsPage,
        ShowsSpace, ReopensArchivedTab, CopiesAnswer, EntersScope, RunsAnswer, RunsCard];

    #endregion

    #region Variables

    public string Name { get; }

    /// The palette closes once the row ran and remembers the pick for what
    /// was typed; otherwise it narrows to what the row names and stays open.
    public bool ClosesPalette { get; }

    /// The keys a person holds choose where the row opens: here, in a new tab
    /// behind or in front, beside it in Split View or in a Quick Window.
    public bool OpensWhereKeysChoose { get; }

    #endregion

    #region Constructors

    private PaletteActivation(string name, bool closesPalette, bool opensWhereKeysChoose) {
        Name = name;
        ClosesPalette = closesPalette;
        OpensWhereKeysChoose = opensWhereKeysChoose;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteActivation? Named(string? name) => All.FirstOrDefault(activation => activation.Name == name);

    #endregion
}
