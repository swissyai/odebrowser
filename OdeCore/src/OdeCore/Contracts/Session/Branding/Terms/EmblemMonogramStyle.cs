namespace OdeCore.Contracts;

/// The letterforms of a monogram charge.
public sealed class EmblemMonogramStyle {
    #region Types

    /// Each platform chooses each style's typeface, so its renderer switches over the kind.
    public enum Kinds { Serif, Sans }

    #endregion

    #region Variables

    public static readonly EmblemMonogramStyle Serif = new(Kinds.Serif, "serif", "Serif", EmblemVocabulary.Studio);
    public static readonly EmblemMonogramStyle Sans = new(Kinds.Sans, "sans", "Sans", EmblemVocabulary.Studio);

    public static IReadOnlyList<EmblemMonogramStyle> All { get; } = [Serif, Sans];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public EmblemVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private EmblemMonogramStyle(Kinds kind, string name, string title, EmblemVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemMonogramStyle? Named(string? name) => All.FirstOrDefault(monogramStyle => monogramStyle.Name == name);

    #endregion
}
