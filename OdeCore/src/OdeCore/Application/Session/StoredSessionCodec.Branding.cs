using System.Text.Json.Nodes;

using OdeCore.Contracts;

namespace OdeCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// Branding stored before rendering versions were recorded is version one.
    private const int FirstRenderingVersion = 1;

    #endregion

    #region Actions - Branding

    /// A Space's branding, with the native reader's defaults for anything missing
    /// and for a term this build cannot name. Colors that are not color records
    /// are left out.
    internal static SpaceBranding DecodeBranding(JsonNode? node) {
        var value = Object(node);
        var (fade, keepsReadable) = DecodeReadability(value);
        return new(Palette(value[Key.Colors]) ?? new([]), Term(value[Key.BannerPattern], SpaceBannerPattern.Named, SpaceBannerPattern.Solid),
            OptionalNumber(value[Key.BannerStrength]) ?? 1, fade, keepsReadable,
            Term(value[Key.ThemeMode], SpaceThemeMode.Named, SpaceThemeMode.Banner),
            OptionalNumber(value[Key.GradientAngle]) ?? 0, Flag(value[Key.ShowsTexture]) ?? false,
            Term(value[Key.IconStyle], SpaceIconStyle.Named, SpaceIconStyle.SimpleSymbol),
            value[Key.SymbolColor] is JsonObject symbolColor ? DecodeColor(symbolColor) : null,
            DecodeEmblem(value[Key.Emblem] as JsonObject ?? []),
            Integer(value[Key.RenderingVersion]) ?? FirstRenderingVersion,
            OptionalNumber(value[Key.FolderColorIntensity]) ?? 0,
            Term(value[Key.TextColorMode], SpaceTextColorMode.Named, SpaceTextColorMode.Automatic),
            Flag(value[Key.HasCustomAppearance]));
    }

    /// How far the banner fades behind the controls and whether they stay
    /// readable. Branding stored before the fade fades by the legacy amount
    /// unless it turned readable controls off; branding without the flag keeps
    /// them readable whenever it fades.
    private static (double Fade, bool KeepsReadable) DecodeReadability(JsonObject value) {
        var stored = OptionalNumber(value[Key.ReadabilityFade]);
        var keepsReadable = Flag(value[Key.KeepsControlsReadable]);
        double fade = stored ?? (keepsReadable ?? true ? SpaceBranding.LegacyReadabilityFade : 0);
        return (fade, keepsReadable ?? fade > 0);
    }

    /// The term `node` names, or `fallback` for a missing one or one this build cannot name.
    private static T Term<T>(JsonNode? node, Func<string?, T?> named, T fallback) where T : class => named(Text(node)) ?? fallback;

    internal static JsonObject Encode(SpaceBranding branding) {
        var value = new JsonObject {
            [Key.Colors] = Encode(branding.Colors),
            [Key.BannerPattern] = branding.BannerPattern.Name,
            [Key.BannerStrength] = branding.BannerStrength,
            [Key.ReadabilityFade] = branding.ReadabilityFade,
            [Key.KeepsControlsReadable] = branding.KeepsControlsReadable,
            [Key.ThemeMode] = branding.ThemeMode.Name,
            [Key.GradientAngle] = branding.GradientAngle,
            [Key.ShowsTexture] = branding.ShowsTexture,
            [Key.IconStyle] = branding.IconStyle.Name
        };
        if (branding.SymbolColor is { } symbolColor) value[Key.SymbolColor] = Encode(symbolColor);
        value[Key.Emblem] = Encode(branding.Emblem);
        value[Key.RenderingVersion] = branding.RenderingVersion;
        value[Key.FolderColorIntensity] = branding.FolderColorIntensity;
        value[Key.TextColorMode] = branding.TextColorMode.Name;
        if (branding.HasCustomAppearance is { } custom) value[Key.HasCustomAppearance] = custom;
        return value;
    }

    /// A emblem composition. Missing layer indices read as the first color, the
    /// edge follows the trim, and every other parameter takes its neutral value.
    internal static SpaceEmblem DecodeEmblem(JsonObject value) {
        int Index(string key, int fallback = 0) => Integer(value[key]) ?? fallback;
        double Measure(EmblemMeasure measure) => OptionalNumber(value[measure.Name]) ?? measure.Default;
        int Count(EmblemMeasure measure) => Integer(value[measure.Name]) ?? (int)measure.Default;
        return new(Term(value[Key.Backplate], EmblemBackplate.Named, EmblemBackplate.Shield),
            Term(value[Key.FieldDivision], EmblemFieldDivision.Named, EmblemFieldDivision.Plain),
            Term(value[Key.Ordinary], EmblemOrdinary.Named, EmblemOrdinary.None),
            Term(value[Key.Trim], EmblemTrim.Named, EmblemTrim.None),
            Term(value[Key.Symbol], EmblemSymbol.Named, EmblemSymbol.Fallback),
            Term(value[Key.ChargeLayout], EmblemChargeLayout.Named, EmblemChargeLayout.Single),
            Index(Key.BackplateColorIndex), Index(Key.SecondaryFieldColorIndex), Index(Key.OrdinaryColorIndex),
            Index(Key.TrimColorIndex), Index(Key.SymbolColorIndex), TolerantText(value[Key.StartingPresetId]),
            Index(Key.EdgeColorIndex, Index(Key.TrimColorIndex)), Palette(value[Key.Palette]),
            value[Key.Charge] is JsonObject charge ? DecodeCharge(charge) : null,
            Measure(EmblemMeasure.PlateScale), Measure(EmblemMeasure.EdgeWidth), Count(EmblemMeasure.DivisionCount),
            Term(value[Key.Finish], EmblemFinish.Named, EmblemFinish.Flat),
            Measure(EmblemMeasure.OrdinaryWidth), Measure(EmblemMeasure.TrimWeight), Count(EmblemMeasure.TrimDetail),
            Measure(EmblemMeasure.ChargeScale), Measure(EmblemMeasure.ChargeOffset),
            Term(value[Key.ChargeWeight], EmblemChargeWeight.Named, EmblemChargeWeight.Bold),
            Measure(EmblemMeasure.SheenAngle), Count(EmblemMeasure.SealTeeth), TolerantFlag(value[Key.ShowsOutline]) ?? false,
            Term(value[Key.Depth], EmblemDepth.Named, EmblemDepth.None));
    }

    internal static JsonObject Encode(SpaceEmblem emblem) {
        var value = new JsonObject {
            [Key.Backplate] = emblem.Backplate.Name,
            [Key.FieldDivision] = emblem.FieldDivision.Name,
            [Key.Ordinary] = emblem.Ordinary.Name,
            [Key.Trim] = emblem.Trim.Name,
            [Key.Symbol] = emblem.Symbol.Name,
            [Key.ChargeLayout] = emblem.ChargeLayout.Name,
            [Key.BackplateColorIndex] = emblem.BackplateColorIndex,
            [Key.SecondaryFieldColorIndex] = emblem.SecondaryFieldColorIndex,
            [Key.OrdinaryColorIndex] = emblem.OrdinaryColorIndex,
            [Key.TrimColorIndex] = emblem.TrimColorIndex,
            [Key.SymbolColorIndex] = emblem.SymbolColorIndex
        };
        Put(value, Key.StartingPresetId, emblem.StartingPresetId);
        value[Key.EdgeColorIndex] = emblem.EdgeColorIndex;
        if (emblem.Palette is { } palette) value[Key.Palette] = Encode(palette);
        if (emblem.Charge is { } charge) value[Key.Charge] = Encode(charge);
        value[EmblemMeasure.PlateScale.Name] = emblem.PlateScale;
        value[EmblemMeasure.EdgeWidth.Name] = emblem.EdgeWidth;
        value[EmblemMeasure.DivisionCount.Name] = emblem.DivisionCount;
        value[Key.Finish] = emblem.Finish.Name;
        value[EmblemMeasure.OrdinaryWidth.Name] = emblem.OrdinaryWidth;
        value[EmblemMeasure.TrimWeight.Name] = emblem.TrimWeight;
        value[EmblemMeasure.TrimDetail.Name] = emblem.TrimDetail;
        value[EmblemMeasure.ChargeScale.Name] = emblem.ChargeScale;
        value[EmblemMeasure.ChargeOffset.Name] = emblem.ChargeOffset;
        value[Key.ChargeWeight] = emblem.ChargeWeight.Name;
        value[EmblemMeasure.SheenAngle.Name] = emblem.SheenAngle;
        value[EmblemMeasure.SealTeeth.Name] = emblem.SealTeeth;
        value[Key.ShowsOutline] = emblem.ShowsOutline;
        value[Key.Depth] = emblem.Depth.Name;
        return value;
    }

    /// A custom figure. An unknown kind draws nothing, a heraldic figure this
    /// build cannot name is the mountain, and a monogram is serif unless it says.
    internal static EmblemCharge DecodeCharge(JsonObject value) {
        var text = TolerantText(value[Key.Value]) ?? "";
        var kind = EmblemChargeKind.Named(TolerantText(value[Key.Kind])) ?? EmblemChargeKind.None;
        return kind.Kind switch {
            EmblemChargeKind.Kinds.Heraldic => new(kind, EmblemSymbol.Named(text) ?? EmblemSymbol.Fallback),
            EmblemChargeKind.Kinds.System or EmblemChargeKind.Kinds.Emoji => new(kind, Text: text),
            EmblemChargeKind.Kinds.Monogram => new(kind, Text: text,
                Style: EmblemMonogramStyle.Named(TolerantText(value[Key.Style])) ?? EmblemMonogramStyle.Serif),
            _ => new(EmblemChargeKind.None)
        };
    }

    internal static JsonObject Encode(EmblemCharge charge) {
        var value = new JsonObject { [Key.Kind] = charge.Kind.Name };
        if (charge.Kind == EmblemChargeKind.Heraldic && charge.Symbol is { } symbol) value[Key.Value] = symbol.Name;
        else if (charge.Kind != EmblemChargeKind.None) value[Key.Value] = charge.Text ?? "";
        if (charge.Kind == EmblemChargeKind.Monogram) value[Key.Style] = (charge.Style ?? EmblemMonogramStyle.Serif).Name;
        return value;
    }

    private static ColorPalette? Palette(JsonNode? node) =>
        node is JsonArray colors ? new([.. colors.OfType<JsonObject>().Select(DecodeColor)]) : null;

    private static JsonArray Encode(ColorPalette palette) => new(palette.Colors.Select(color => (JsonNode?)Encode(color)).ToArray());

    #endregion
}
