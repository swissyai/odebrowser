using OdeCore.Domain;

namespace OdeCore.Contracts;

/// The range rules for a Space's banner branding. The emblem's heraldic vocabulary
/// stays with the native renderer; the core owns the palette size, the banner
/// strengths, the gradient angle, the emblem's layer colors pointing at a color
/// that exists, its composition parameters within the ranges the renderer draws
/// and its custom figure, so the branding the core stages for sync is the one
/// every device renders.
public sealed partial record SpaceBranding {
    #region Static Variables

    internal const int MaximumColorCount = 3;
    internal const int MaximumEmblemPaletteCount = 6;

    /// The Space color used when a branding record has none.
    internal static BrandColor DefaultColor { get; } = new(0.29, 0.25, 0.58);

    #endregion

    #region Actions - Normalization

    /// The branding with every rule the core owns applied, as every client
    /// writes it: its banner strength in today's units, at most three colors
    /// and never none, strengths, fades and color components within 0 through
    /// 1, the gradient angle within a turn, and emblem layers addressing a color
    /// that exists. The emblem's own palette is dropped when it holds no color,
    /// its composition parameters stay within the ranges the renderer draws,
    /// and a custom figure that is the emblem's own symbol is no custom figure.
    /// It announces the readability and rendering vocabulary its values need.
    internal static SpaceBranding Normalized(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        branding = branding.InTodaysUnits();
        var colors = branding.Colors.Colors.Take(MaximumColorCount).Select(NormalizedColor).ToArray();
        if (colors.Length == 0) colors = [DefaultColor];
        var palette = branding.Emblem.Palette?.Colors.Take(MaximumEmblemPaletteCount).Select(NormalizedColor).ToArray();
        if (palette is { Length: 0 }) palette = null;
        int layers = LayerColorCount(palette?.Length, colors.Length);
        var emblem = branding.Emblem;
        return Announced(branding with {
            Colors = new(colors),
            BannerStrength = Unit(branding.BannerStrength),
            ReadabilityFade = Unit(branding.ReadabilityFade),
            GradientAngle = NormalizedAngle(branding.GradientAngle),
            FolderColorIntensity = Unit(branding.FolderColorIntensity),
            SymbolColor = branding.SymbolColor is { } symbol ? NormalizedColor(symbol) : null,
            Emblem = emblem with {
                Palette = palette is null ? null : new(palette),
                BackplateColorIndex = LayerIndex(emblem.BackplateColorIndex, layers),
                SecondaryFieldColorIndex = LayerIndex(emblem.SecondaryFieldColorIndex, layers),
                OrdinaryColorIndex = LayerIndex(emblem.OrdinaryColorIndex, layers),
                TrimColorIndex = LayerIndex(emblem.TrimColorIndex, layers),
                SymbolColorIndex = LayerIndex(emblem.SymbolColorIndex, layers),
                EdgeColorIndex = LayerIndex(emblem.EdgeColorIndex, layers),
                Charge = NormalizedCharge(emblem.Charge, emblem.Symbol),
                PlateScale = EmblemMeasure.PlateScale.Clamped(emblem.PlateScale),
                EdgeWidth = EmblemMeasure.EdgeWidth.Clamped(emblem.EdgeWidth),
                DivisionCount = EmblemMeasure.DivisionCount.Clamped(emblem.DivisionCount),
                OrdinaryWidth = EmblemMeasure.OrdinaryWidth.Clamped(emblem.OrdinaryWidth),
                TrimWeight = EmblemMeasure.TrimWeight.Clamped(emblem.TrimWeight),
                TrimDetail = EmblemMeasure.TrimDetail.Clamped(emblem.TrimDetail),
                ChargeScale = EmblemMeasure.ChargeScale.Clamped(emblem.ChargeScale),
                ChargeOffset = EmblemMeasure.ChargeOffset.Clamped(emblem.ChargeOffset),
                SheenAngle = EmblemMeasure.SheenAngle.Clamped(emblem.SheenAngle),
                SealTeeth = EmblemMeasure.SealTeeth.Clamped(emblem.SealTeeth)
            }
        });
    }

    /// `look` with the readability and rendering vocabulary it announces worked
    /// out from its values.
    internal static SpaceBranding Announced(SpaceBranding look) {
        ArgumentNullException.ThrowIfNull(look);
        return look with { KeepsControlsReadable = look.ReadabilityFade > 0, RenderingVersion = NeededRenderingVersion(look) };
    }

    /// A emblem's custom figure as the renderer draws it: names and letters
    /// trimmed, one emoji, a monogram of at most two capitals, nothing drawn in
    /// place of an empty one, and none at all when it is the emblem's own symbol.
    private static EmblemCharge? NormalizedCharge(EmblemCharge? charge, EmblemSymbol symbol) {
        if (charge is null) return null;
        var figure = charge.Kind.Normalized(charge);
        return figure.Kind == EmblemChargeKind.Heraldic && figure.Symbol == symbol ? null : figure;
    }

    /// A strength, fade, intensity or color component, kept within 0 through 1.
    /// A value that is not a number falls back to `fallback`.
    private static double Unit(double value, double fallback = 0) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : fallback;

    /// Degrees in [0, 360).
    private static double NormalizedAngle(double angle) {
        if (!double.IsFinite(angle)) return 0;
        double remainder = angle % 360;
        return remainder >= 0 ? remainder : remainder + 360;
    }

    /// How many colors a emblem's layer indices can address: its own palette
    /// when it has one, else the Space's colors, and never fewer than one.
    private static int LayerColorCount(int? emblemPaletteCount, int spaceColorCount) =>
        Math.Max(emblemPaletteCount ?? spaceColorCount, 1);

    /// A layer index outside the addressable colors falls back to the first.
    private static int LayerIndex(int index, int colorCount) => index >= 0 && index < colorCount ? index : 0;

    private static BrandColor NormalizedColor(BrandColor color) =>
        new(Unit(color.Red), Unit(color.Green), Unit(color.Blue), Unit(color.Alpha, 1));

    #endregion

    #region Actions - Rendering vocabulary

    /// The rendering vocabulary `branding` needs, which is the version it
    /// announces: the newest vocabulary any of its terms is drawn since, and
    /// the Studio's when it sets a Studio parameter or a color of its own.
    /// Every Apple client computes it this way when it writes a branding.
    internal static int NeededRenderingVersion(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        var emblem = branding.Emblem;
        EmblemVocabulary[] needed = [
            branding.BannerPattern.DrawnSince, emblem.Symbol.DrawnSince, emblem.Backplate.DrawnSince, emblem.FieldDivision.DrawnSince,
            emblem.Ordinary.DrawnSince, emblem.Trim.DrawnSince, emblem.ChargeLayout.DrawnSince, emblem.Finish.DrawnSince,
            emblem.Depth.DrawnSince, emblem.ChargeWeight.DrawnSince,
            branding.SymbolColor is null ? EmblemVocabulary.Baseline : EmblemVocabulary.Customization,
            UsesStudioParameters(emblem) ? EmblemVocabulary.Studio : EmblemVocabulary.Baseline
        ];
        return needed.Max(vocabulary => vocabulary.Version);
    }

    /// Whether the emblem moves a measure only the Studio vocabulary draws off
    /// its default, draws an outline, or wears colors or a figure of its own.
    private static bool UsesStudioParameters(SpaceEmblem emblem) =>
        emblem.Palette is not null || emblem.Charge is not null || emblem.ShowsOutline
        || EmblemMeasure.All.Any(measure => measure.IsMoved(emblem));

    #endregion
}
