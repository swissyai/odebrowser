namespace OdeCore.Contracts;

/// How a emblem's field is divided.
public sealed class EmblemFieldDivision {
    #region Types

    /// Each platform draws each division's geometry, so its renderer switches over the kind.
    public enum Kinds { Plain, PerPale, PerFess, PerBend, PerChevron, Quarterly, PerSaltire, Gyronny, Barry, Paly, Checky }

    #endregion

    #region Variables

    // Titles are one word: they caption gallery cards that already show the division.
    public static readonly EmblemFieldDivision Plain = new(Kinds.Plain, "plain", "Plain", EmblemVocabulary.Baseline);
    public static readonly EmblemFieldDivision PerPale = new(Kinds.PerPale, "perPale", "Vertical", EmblemVocabulary.Baseline);
    public static readonly EmblemFieldDivision PerFess = new(Kinds.PerFess, "perFess", "Horizontal", EmblemVocabulary.Baseline);
    public static readonly EmblemFieldDivision PerBend = new(Kinds.PerBend, "perBend", "Diagonal", EmblemVocabulary.Baseline);
    public static readonly EmblemFieldDivision PerChevron = new(Kinds.PerChevron, "perChevron", "Chevron", EmblemVocabulary.Baseline);
    public static readonly EmblemFieldDivision Quarterly = new(Kinds.Quarterly, "quarterly", "Quartered", EmblemVocabulary.Baseline);
    public static readonly EmblemFieldDivision PerSaltire = new(Kinds.PerSaltire, "perSaltire", "Crossed", EmblemVocabulary.Studio);
    public static readonly EmblemFieldDivision Gyronny = new(Kinds.Gyronny, "gyronny", "Wedges", EmblemVocabulary.Studio, isCounted: true);
    public static readonly EmblemFieldDivision Barry = new(Kinds.Barry, "barry", "Bars", EmblemVocabulary.Studio, isCounted: true);
    public static readonly EmblemFieldDivision Paly = new(Kinds.Paly, "paly", "Stripes", EmblemVocabulary.Studio, isCounted: true);
    public static readonly EmblemFieldDivision Checky = new(Kinds.Checky, "checky", "Checks", EmblemVocabulary.Studio, isCounted: true);

    public static IReadOnlyList<EmblemFieldDivision> All { get; } =
        [Plain, PerPale, PerFess, PerBend, PerChevron, Quarterly, PerSaltire, Gyronny, Barry, Paly, Checky];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The division's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the division.
    public EmblemVocabulary DrawnSince { get; }

    /// Whether the division repeats a number of pieces, and so reads the
    /// emblem's division count.
    public bool IsCounted { get; }

    #endregion

    #region Constructors

    private EmblemFieldDivision(Kinds kind, string name, string title, EmblemVocabulary drawnSince, bool isCounted = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        IsCounted = isCounted;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemFieldDivision? Named(string? name) => All.FirstOrDefault(division => division.Name == name);

    #endregion
}
