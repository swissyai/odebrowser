namespace OdeCore.Contracts;

/// <summary>
/// The composition of a Space's emblem. Layer color indices point into the emblem's own
/// <see cref="Palette"/> when it has one, else into the Space's colors. A
/// <see cref="Charge"/> replaces the heraldic <see cref="Symbol"/> as the figure drawn.
/// </summary>
public sealed record SpaceEmblem(
    EmblemBackplate Backplate,
    EmblemFieldDivision FieldDivision,
    EmblemOrdinary Ordinary,
    EmblemTrim Trim,
    EmblemSymbol Symbol,
    EmblemChargeLayout ChargeLayout,
    int BackplateColorIndex,
    int SecondaryFieldColorIndex,
    int OrdinaryColorIndex,
    int TrimColorIndex,
    int SymbolColorIndex,
    string? StartingPresetId,
    int EdgeColorIndex,
    ColorPalette? Palette,
    EmblemCharge? Charge,
    double PlateScale,
    double EdgeWidth,
    int DivisionCount,
    EmblemFinish Finish,
    double OrdinaryWidth,
    double TrimWeight,
    int TrimDetail,
    double ChargeScale,
    double ChargeOffset,
    EmblemChargeWeight ChargeWeight,
    double SheenAngle,
    int SealTeeth,
    bool ShowsOutline,
    EmblemDepth Depth) {
    #region Static Variables

    /// How many pieces a counted field division draws unless set.
    public const int DefaultDivisionCount = 4;

    /// How much detail a counted trim draws unless set.
    public const int DefaultTrimDetail = 12;

    #endregion

    #region Actions - Compositions

    /// <summary>A plain-field emblem with no ordinary, charged with <paramref name="figure"/>.
    /// <paramref name="layers"/> addresses, in order, the backplate, the second field, the
    /// ordinary, the trim, the figure and the edge; every other parameter is neutral.</summary>
    public static SpaceEmblem PlainField(EmblemBackplate backplate, EmblemSymbol figure, EmblemTrim trim, IReadOnlyList<int> layers,
        double trimWeight, double chargeScale) {
        ArgumentNullException.ThrowIfNull(layers);
        return new(backplate, EmblemFieldDivision.Plain, EmblemOrdinary.None, trim, figure, EmblemChargeLayout.Single,
            BackplateColorIndex: layers[0], SecondaryFieldColorIndex: layers[1], OrdinaryColorIndex: layers[2], TrimColorIndex: layers[3],
            SymbolColorIndex: layers[4], StartingPresetId: null, EdgeColorIndex: layers[5], Palette: null, Charge: null, PlateScale: 1,
            EdgeWidth: 0, DivisionCount: DefaultDivisionCount, EmblemFinish.Flat, OrdinaryWidth: 1, trimWeight,
            TrimDetail: DefaultTrimDetail, chargeScale, ChargeOffset: 0, EmblemChargeWeight.Bold, SheenAngle: 45, SealTeeth: 12,
            ShowsOutline: false, EmblemDepth.None);
    }

    #endregion
}
