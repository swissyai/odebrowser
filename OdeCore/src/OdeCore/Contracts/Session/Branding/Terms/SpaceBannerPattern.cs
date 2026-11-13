namespace OdeCore.Contracts;

/// How a Space's banner arranges its colors.
public sealed class SpaceBannerPattern {
    #region Types

    /// Each platform draws each pattern, so its renderer switches over the kind.
    public enum Kinds { Solid, Split, Bands, Diagonal, Chevron, Quartered, Stripes, Checkered, Lozenges }

    #endregion

    #region Variables

    public static readonly SpaceBannerPattern Solid = new(Kinds.Solid, "solid", "Solid", EmblemVocabulary.Baseline);
    public static readonly SpaceBannerPattern Split = new(Kinds.Split, "split", "Split", EmblemVocabulary.Baseline);
    public static readonly SpaceBannerPattern Bands = new(Kinds.Bands, "bands", "Bands", EmblemVocabulary.Baseline);
    public static readonly SpaceBannerPattern Diagonal = new(Kinds.Diagonal, "diagonal", "Diagonal", EmblemVocabulary.Baseline);
    public static readonly SpaceBannerPattern Chevron = new(Kinds.Chevron, "chevron", "Chevron", EmblemVocabulary.Baseline);
    public static readonly SpaceBannerPattern Quartered = new(Kinds.Quartered, "quartered", "Quartered", EmblemVocabulary.Baseline);
    public static readonly SpaceBannerPattern Stripes = new(Kinds.Stripes, "stripes", "Stripes", EmblemVocabulary.Customization);
    public static readonly SpaceBannerPattern Checkered = new(Kinds.Checkered, "checkered", "Checkered", EmblemVocabulary.Customization);
    public static readonly SpaceBannerPattern Lozenges = new(Kinds.Lozenges, "lozenges", "Lozenges", EmblemVocabulary.Customization);

    public static IReadOnlyList<SpaceBannerPattern> All { get; } = [Solid, Split, Bands, Diagonal, Chevron, Quartered, Stripes, Checkered, Lozenges];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public EmblemVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private SpaceBannerPattern(Kinds kind, string name, string title, EmblemVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceBannerPattern? Named(string? name) => All.FirstOrDefault(bannerPattern => bannerPattern.Name == name);

    #endregion
}
