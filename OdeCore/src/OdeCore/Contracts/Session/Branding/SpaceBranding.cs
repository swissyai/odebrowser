namespace OdeCore.Contracts;

/// <summary>
/// How a Space's sidebar and icon look. <see cref="RenderingVersion"/> is the newest
/// vocabulary the branding uses, which older readers need to read it faithfully.
/// <see cref="HasCustomAppearance"/> is null for branding stored before it was recorded.
/// </summary>
public sealed partial record SpaceBranding(
    ColorPalette Colors,
    SpaceBannerPattern BannerPattern,
    double BannerStrength,
    double ReadabilityFade,
    bool KeepsControlsReadable,
    SpaceThemeMode ThemeMode,
    double GradientAngle,
    bool ShowsTexture,
    SpaceIconStyle IconStyle,
    BrandColor? SymbolColor,
    SpaceEmblem Emblem,
    int RenderingVersion,
    double FolderColorIntensity,
    SpaceTextColorMode TextColorMode,
    bool? HasCustomAppearance) {
    #region Static Variables

    /// The rendering vocabulary every shipped build draws. A banner strength stored
    /// with an older version is in the units the first builds drew.
    public const int BaselineRenderingVersion = 2;

    /// The fade a branding from before readability fades wears for its old switch.
    public const double LegacyReadabilityFade = 0.25;

    /// <summary>The quiet look a Space from another browser wears when that browser
    /// gave it no colors: a gray solid banner that keeps controls readable, with a
    /// plain mountain emblem.</summary>
    public static SpaceBranding Neutral { get; } = new(new([new(0.24, 0.25, 0.27)]), SpaceBannerPattern.Solid, BannerStrength: 1,
        ReadabilityFade: 0.34, KeepsControlsReadable: true, SpaceThemeMode.Banner, GradientAngle: 0, ShowsTexture: false,
        SpaceIconStyle.SimpleSymbol, SymbolColor: null,
        SpaceEmblem.PlainField(EmblemBackplate.Shield, EmblemSymbol.Mountain, EmblemTrim.None, layers: [1, 1, 2, 1, 2, 1], trimWeight: 1,
            chargeScale: 1),
        BaselineRenderingVersion, FolderColorIntensity: 0, SpaceTextColorMode.Automatic, HasCustomAppearance: null);

    #endregion

    #region Actions - Looks

    /// <summary>This branding with a banner strength stored before the baseline
    /// vocabulary in today's units, <c>min(1, 0.72 + strength × 0.28)</c>, which it then
    /// announces as the baseline. Branding at the baseline or later is already in them.</summary>
    public SpaceBranding InTodaysUnits() => RenderingVersion >= BaselineRenderingVersion
        ? this
        : this with { BannerStrength = Math.Min(1, 0.72 + BannerStrength * 0.28), RenderingVersion = BaselineRenderingVersion };

    /// <summary>The look a Space stored before branding existed wears: its accent's
    /// legacy colors in a diagonal banner at full strength that keeps controls readable,
    /// with a plain shield emblem whose figure its SF Symbol suggests.</summary>
    public static SpaceBranding Legacy(SpaceAccent accent, string symbol) {
        ArgumentNullException.ThrowIfNull(accent);
        ArgumentNullException.ThrowIfNull(symbol);
        var emblem = SpaceEmblem.PlainField(EmblemBackplate.Shield, LegacyFigure(symbol), EmblemTrim.None, layers: [1, 1, 2, 1, 2, 1],
            trimWeight: 1, chargeScale: 1);
        return new(new(accent.LegacyColors), SpaceBannerPattern.Diagonal, BannerStrength: 1, LegacyReadabilityFade,
            KeepsControlsReadable: true, SpaceThemeMode.Banner, GradientAngle: 0, ShowsTexture: false, SpaceIconStyle.SimpleSymbol,
            SymbolColor: null, emblem, BaselineRenderingVersion, FolderColorIntensity: 0, SpaceTextColorMode.Automatic,
            HasCustomAppearance: null);
    }

    /// The emblem figure an SF Symbol name suggested before emblems had their own.
    public static EmblemSymbol LegacyFigure(string symbol) =>
        symbol.Contains("leaf", StringComparison.Ordinal) ? EmblemSymbol.Leaf
        : symbol.Contains("book", StringComparison.Ordinal) || symbol.Contains("graduation", StringComparison.Ordinal) ? EmblemSymbol.Book
        : symbol.Contains("key", StringComparison.Ordinal) ? EmblemSymbol.Key
        : symbol.Contains("flame", StringComparison.Ordinal) ? EmblemSymbol.Flame
        : symbol.Contains("compass", StringComparison.Ordinal) || symbol.Contains("location", StringComparison.Ordinal) ? EmblemSymbol.Compass
        : symbol.Contains("sun", StringComparison.Ordinal) ? EmblemSymbol.Sun
        : EmblemSymbol.Mountain;

    #endregion
}
