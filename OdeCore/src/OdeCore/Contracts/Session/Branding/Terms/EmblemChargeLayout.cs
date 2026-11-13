namespace OdeCore.Contracts;

/// How many figures a emblem repeats, and how.
public sealed class EmblemChargeLayout {
    #region Types

    /// Each platform places each arrangement's figures, so its renderer switches over the kind.
    public enum Kinds { Single, Paired, Trio, Quad, Ring }

    #endregion

    #region Variables

    public static readonly EmblemChargeLayout Single = new(Kinds.Single, "single", "One", EmblemVocabulary.Baseline);
    public static readonly EmblemChargeLayout Paired = new(Kinds.Paired, "paired", "Two", EmblemVocabulary.Baseline);
    public static readonly EmblemChargeLayout Trio = new(Kinds.Trio, "trio", "Three", EmblemVocabulary.Baseline);
    public static readonly EmblemChargeLayout Quad = new(Kinds.Quad, "quad", "Four", EmblemVocabulary.Studio);
    public static readonly EmblemChargeLayout Ring = new(Kinds.Ring, "ring", "Ring", EmblemVocabulary.Studio);

    public static IReadOnlyList<EmblemChargeLayout> All { get; } = [Single, Paired, Trio, Quad, Ring];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public EmblemVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private EmblemChargeLayout(Kinds kind, string name, string title, EmblemVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemChargeLayout? Named(string? name) => All.FirstOrDefault(chargeLayout => chargeLayout.Name == name);

    #endregion
}
