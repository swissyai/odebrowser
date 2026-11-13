namespace OdeCore.Contracts;

/// The border drawn around a emblem.
public sealed class EmblemTrim {
    #region Types

    /// Each platform draws each border, so its renderer switches over the kind.
    public enum Kinds { None, Shield, Line, DoubleLine, Laurel, Sunburst, DoubleRing, Seal, Beaded }

    #endregion

    #region Variables

    public static readonly EmblemTrim None = new(Kinds.None, "none", "None", EmblemVocabulary.Baseline);
    public static readonly EmblemTrim Shield = new(Kinds.Shield, "shield", "Shield", EmblemVocabulary.Baseline);
    public static readonly EmblemTrim Line = new(Kinds.Line, "line", "Line", EmblemVocabulary.Studio);
    public static readonly EmblemTrim DoubleLine = new(Kinds.DoubleLine, "doubleLine", "Double Line", EmblemVocabulary.Studio);
    public static readonly EmblemTrim Laurel = new(Kinds.Laurel, "laurel", "Laurel", EmblemVocabulary.Baseline);
    public static readonly EmblemTrim Sunburst = new(Kinds.Sunburst, "sunburst", "Sunburst", EmblemVocabulary.Baseline, isCounted: true);
    public static readonly EmblemTrim DoubleRing = new(Kinds.DoubleRing, "doubleRing", "Double Ring", EmblemVocabulary.Baseline);
    public static readonly EmblemTrim Seal = new(Kinds.Seal, "seal", "Seal", EmblemVocabulary.Baseline);
    public static readonly EmblemTrim Beaded = new(Kinds.Beaded, "beaded", "Beaded", EmblemVocabulary.Studio, isCounted: true);

    public static IReadOnlyList<EmblemTrim> All { get; } = [None, Shield, Line, DoubleLine, Laurel, Sunburst, DoubleRing, Seal, Beaded];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The border's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the border.
    public EmblemVocabulary DrawnSince { get; }

    /// Whether the border is made of repeated elements, and so reads the
    /// emblem's trim detail.
    public bool IsCounted { get; }

    #endregion

    #region Constructors

    private EmblemTrim(Kinds kind, string name, string title, EmblemVocabulary drawnSince, bool isCounted = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        IsCounted = isCounted;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemTrim? Named(string? name) => All.FirstOrDefault(trim => trim.Name == name);

    #endregion
}
