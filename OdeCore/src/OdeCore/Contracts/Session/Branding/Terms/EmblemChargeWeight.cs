namespace OdeCore.Contracts;

/// The stroke weight of a emblem's figure.
public sealed class EmblemChargeWeight {
    #region Types

    /// Each platform maps each weight to its own font weight, so its renderer switches over the kind.
    public enum Kinds { Light, Regular, Bold }

    #endregion

    #region Variables

    public static readonly EmblemChargeWeight Light = new(Kinds.Light, "light", "Light", EmblemVocabulary.Studio);
    public static readonly EmblemChargeWeight Regular = new(Kinds.Regular, "regular", "Regular", EmblemVocabulary.Studio);
    public static readonly EmblemChargeWeight Bold = new(Kinds.Bold, "bold", "Bold", EmblemVocabulary.Baseline);

    public static IReadOnlyList<EmblemChargeWeight> All { get; } = [Light, Regular, Bold];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public EmblemVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private EmblemChargeWeight(Kinds kind, string name, string title, EmblemVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemChargeWeight? Named(string? name) => All.FirstOrDefault(chargeWeight => chargeWeight.Name == name);

    #endregion
}
