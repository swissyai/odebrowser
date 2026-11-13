namespace OdeCore.Contracts;

/// How far a emblem stands off the banner.
public sealed class EmblemDepth {
    #region Types

    /// Each platform casts each depth's shadow, so its renderer switches over the kind.
    public enum Kinds { None, Soft, Lifted }

    #endregion

    #region Variables

    public static readonly EmblemDepth None = new(Kinds.None, "none", "None", EmblemVocabulary.Baseline);
    public static readonly EmblemDepth Soft = new(Kinds.Soft, "soft", "Soft", EmblemVocabulary.Studio);
    public static readonly EmblemDepth Lifted = new(Kinds.Lifted, "lifted", "Lifted", EmblemVocabulary.Studio);

    public static IReadOnlyList<EmblemDepth> All { get; } = [None, Soft, Lifted];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public EmblemVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private EmblemDepth(Kinds kind, string name, string title, EmblemVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemDepth? Named(string? name) => All.FirstOrDefault(depth => depth.Name == name);

    #endregion
}
