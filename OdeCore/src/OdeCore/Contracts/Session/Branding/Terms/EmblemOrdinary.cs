namespace OdeCore.Contracts;

/// The band or cross laid over a emblem's field.
public sealed class EmblemOrdinary {
    #region Types

    /// Each platform draws each band's path, so its renderer switches over the kind.
    public enum Kinds { None, Pale, Fess, Bend, Chevron, Cross, Saltire, Chief, Bordure, Pall, Pile, Canton, Roundel }

    #endregion

    #region Variables

    public static readonly EmblemOrdinary None = new(Kinds.None, "none", "None", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Pale = new(Kinds.Pale, "pale", "Pale", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Fess = new(Kinds.Fess, "fess", "Fess", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Bend = new(Kinds.Bend, "bend", "Bend", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Chevron = new(Kinds.Chevron, "chevron", "Chevron", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Cross = new(Kinds.Cross, "cross", "Cross", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Saltire = new(Kinds.Saltire, "saltire", "Saltire", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Chief = new(Kinds.Chief, "chief", "Chief", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Bordure = new(Kinds.Bordure, "bordure", "Bordure", EmblemVocabulary.Baseline);
    public static readonly EmblemOrdinary Pall = new(Kinds.Pall, "pall", "Pall", EmblemVocabulary.Studio);
    public static readonly EmblemOrdinary Pile = new(Kinds.Pile, "pile", "Pile", EmblemVocabulary.Studio);
    public static readonly EmblemOrdinary Canton = new(Kinds.Canton, "canton", "Canton", EmblemVocabulary.Studio);
    public static readonly EmblemOrdinary Roundel = new(Kinds.Roundel, "roundel", "Roundel", EmblemVocabulary.Studio);

    public static IReadOnlyList<EmblemOrdinary> All { get; } =
        [None, Pale, Fess, Bend, Chevron, Cross, Saltire, Chief, Bordure, Pall, Pile, Canton, Roundel];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The band's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the band.
    public EmblemVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private EmblemOrdinary(Kinds kind, string name, string title, EmblemVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemOrdinary? Named(string? name) => All.FirstOrDefault(ordinary => ordinary.Name == name);

    #endregion
}
