namespace OdeCore.Contracts;

/// A number that sizes, counts or turns part of a crest: the range the
/// renderer draws it in, the value it takes unless set, and the emblems it
/// shapes at all.
public sealed class EmblemMeasure {
    #region Variables

    public static readonly EmblemMeasure PlateScale = new("plateScale", 0.7, 1.15, 1, emblem => emblem.PlateScale);
    public static readonly EmblemMeasure EdgeWidth = new("edgeWidth", 0, 1, 0, emblem => emblem.EdgeWidth);
    public static readonly EmblemMeasure DivisionCount = new("divisionCount", 2, 8, SpaceEmblem.DefaultDivisionCount, emblem => emblem.DivisionCount,
        emblem => emblem.FieldDivision.IsCounted, isCount: true);
    public static readonly EmblemMeasure OrdinaryWidth = new("ordinaryWidth", 0.5, 1.6, 1, emblem => emblem.OrdinaryWidth);
    public static readonly EmblemMeasure TrimWeight = new("trimWeight", 0.5, 2, 1, emblem => emblem.TrimWeight);
    public static readonly EmblemMeasure TrimDetail = new("trimDetail", 6, 24, SpaceEmblem.DefaultTrimDetail, emblem => emblem.TrimDetail,
        emblem => emblem.Trim.IsCounted, isCount: true);
    public static readonly EmblemMeasure ChargeScale = new("chargeScale", 0.6, 1.5, 1, emblem => emblem.ChargeScale);
    public static readonly EmblemMeasure ChargeOffset = new("chargeOffset", -0.2, 0.2, 0, emblem => emblem.ChargeOffset);
    public static readonly EmblemMeasure SheenAngle = new("sheenAngle", 0, 360, 45, emblem => emblem.SheenAngle);
    public static readonly EmblemMeasure SealTeeth = new("sealTeeth", 6, 24, 12, emblem => emblem.SealTeeth,
        emblem => emblem.Backplate.HasTeeth, isCount: true);

    public static IReadOnlyList<EmblemMeasure> All { get; } =
        [PlateScale, EdgeWidth, DivisionCount, OrdinaryWidth, TrimWeight, TrimDetail, ChargeScale, ChargeOffset, SheenAngle, SealTeeth];

    public string Name { get; }
    public double Minimum { get; }
    public double Maximum { get; }

    /// The value a emblem takes unless set, and which the Studio vocabulary is
    /// needed to draw it away from.
    public double Default { get; }

    /// Whether the measure counts whole pieces rather than sizing them.
    public bool IsCount { get; }

    private readonly Func<SpaceEmblem, double> value;
    private readonly Func<SpaceEmblem, bool> shapes;

    #endregion

    #region Constructors

    private EmblemMeasure(string name, double minimum, double maximum, double defaultValue, Func<SpaceEmblem, double> value,
        Func<SpaceEmblem, bool>? shapes = null, bool isCount = false) {
        Name = name;
        Minimum = minimum;
        Maximum = maximum;
        Default = defaultValue;
        IsCount = isCount;
        this.value = value;
        this.shapes = shapes ?? (_ => true);
    }

    #endregion

    #region Actions - Lookup

    public static EmblemMeasure? Named(string? name) => All.FirstOrDefault(measure => measure.Name == name);

    #endregion

    #region Actions - Values

    /// `measure` within the range; one that is not a number takes the default.
    public double Clamped(double measure) => double.IsFinite(measure) ? Math.Clamp(measure, Minimum, Maximum) : Default;

    /// A count within the range.
    public int Clamped(int count) => Math.Clamp(count, (int)Minimum, (int)Maximum);

    /// Whether `crest` draws this measure away from its default.
    public bool IsMoved(SpaceEmblem emblem) {
        ArgumentNullException.ThrowIfNull(emblem);
        return shapes(emblem) && value(emblem) != Default;
    }

    #endregion
}
