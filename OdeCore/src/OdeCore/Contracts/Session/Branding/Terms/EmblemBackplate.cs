namespace OdeCore.Contracts;

/// The shape a emblem is drawn on.
public sealed class EmblemBackplate {
    #region Types

    /// Each platform draws each shape's outline, so its renderer switches over the kind.
    public enum Kinds { None, Circle, Shield, FrenchShield, Diamond, Seal, Hexagon, Octagon, RoundedSquare, Oval, Banner, Badge }

    #endregion

    #region Variables

    public static readonly EmblemBackplate None = new(Kinds.None, "none", "None", EmblemVocabulary.Baseline);
    public static readonly EmblemBackplate Circle = new(Kinds.Circle, "circle", "Round", EmblemVocabulary.Baseline);
    public static readonly EmblemBackplate Shield = new(Kinds.Shield, "shield", "Shield", EmblemVocabulary.Baseline);
    public static readonly EmblemBackplate FrenchShield = new(Kinds.FrenchShield, "frenchShield", "French Shield", EmblemVocabulary.Studio);
    public static readonly EmblemBackplate Diamond = new(Kinds.Diamond, "diamond", "Lozenge", EmblemVocabulary.Baseline);
    public static readonly EmblemBackplate Seal = new(Kinds.Seal, "seal", "Seal", EmblemVocabulary.Baseline, hasTeeth: true);
    public static readonly EmblemBackplate Hexagon = new(Kinds.Hexagon, "hexagon", "Hexagon", EmblemVocabulary.Baseline);
    public static readonly EmblemBackplate Octagon = new(Kinds.Octagon, "octagon", "Octagon", EmblemVocabulary.Customization);
    public static readonly EmblemBackplate RoundedSquare = new(Kinds.RoundedSquare, "roundedSquare", "Rounded Square",
        EmblemVocabulary.Customization);
    public static readonly EmblemBackplate Oval = new(Kinds.Oval, "oval", "Oval", EmblemVocabulary.Studio);
    public static readonly EmblemBackplate Banner = new(Kinds.Banner, "banner", "Banner", EmblemVocabulary.Studio);
    public static readonly EmblemBackplate Badge = new(Kinds.Badge, "badge", "Badge", EmblemVocabulary.Studio);

    public static IReadOnlyList<EmblemBackplate> All { get; } =
        [None, Circle, Shield, FrenchShield, Diamond, Seal, Hexagon, Octagon, RoundedSquare, Oval, Banner, Badge];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The shape's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the shape.
    public EmblemVocabulary DrawnSince { get; }

    /// Whether the shape's edge is scalloped, and so reads the emblem's seal teeth.
    public bool HasTeeth { get; }

    #endregion

    #region Constructors

    private EmblemBackplate(Kinds kind, string name, string title, EmblemVocabulary drawnSince, bool hasTeeth = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        HasTeeth = hasTeeth;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemBackplate? Named(string? name) => All.FirstOrDefault(backplate => backplate.Name == name);

    #endregion
}
