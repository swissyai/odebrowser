namespace OdeCore.Contracts;

/// The surface a emblem is rendered with.
public sealed class EmblemFinish {
    #region Types

    /// Each platform paints each finish, so its renderer switches over the kind.
    public enum Kinds { Flat, Sheen, Embossed }

    #endregion

    #region Variables

    public static readonly EmblemFinish Flat = new(Kinds.Flat, "flat", "Flat", EmblemVocabulary.Baseline);
    public static readonly EmblemFinish Sheen = new(Kinds.Sheen, "sheen", "Sheen", EmblemVocabulary.Studio, hasAngle: true);
    public static readonly EmblemFinish Embossed = new(Kinds.Embossed, "embossed", "Embossed", EmblemVocabulary.Studio);

    public static IReadOnlyList<EmblemFinish> All { get; } = [Flat, Sheen, Embossed];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public EmblemVocabulary DrawnSince { get; }

    /// Whether the finish's light falls from a direction, and so reads the emblem's sheen angle.
    public bool HasAngle { get; }

    #endregion

    #region Constructors

    private EmblemFinish(Kinds kind, string name, string title, EmblemVocabulary drawnSince, bool hasAngle = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        HasAngle = hasAngle;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemFinish? Named(string? name) => All.FirstOrDefault(finish => finish.Name == name);

    #endregion
}
