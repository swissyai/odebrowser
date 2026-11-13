namespace OdeCore.Contracts;

/// A look a Space can start from: a house's arms on a sidebar in the house's
/// colors and its own background. Choosing one copies its look into the Space,
/// so a Space keeps the look it was given when a house changes.
public sealed class SpaceHouse {
    #region Variables

    /// A grey direwolf on a field of snow.
    public static readonly SpaceHouse Winter = new("winter", "Winter", "CrestWinter", HouseLook(
        [Tincture.WinterSlate, Tincture.WinterSteel, Tincture.WinterIce], SpaceThemeMode.Banner, SpaceBannerPattern.Diagonal,
        Arms(EmblemBackplate.FrenchShield, EmblemSymbol.Direwolf, EmblemTrim.Line, edgeWidth: 0.35,
            [Tincture.WinterArgent, Tincture.WinterIce, Tincture.WinterSteel, Tincture.WinterWolf, Tincture.WinterSteel,
                Tincture.WinterSlate])));

    /// A golden lion on crimson, its double border and its sheen in gold.
    public static readonly SpaceHouse Lion = new("lion", "Lion", "CrestLion", HouseLook(
        [Tincture.LionOxblood, Tincture.LionCrimson, Tincture.LionGold], SpaceThemeMode.Banner, SpaceBannerPattern.Chevron,
        Arms(EmblemBackplate.Shield, EmblemSymbol.Lion, EmblemTrim.DoubleLine, edgeWidth: 0.25,
            [Tincture.LionGules, Tincture.LionCrimson, Tincture.LionOr, Tincture.LionOr, Tincture.LionOr, Tincture.LionOxblood],
            chargeScale: 1.25, trimWeight: 0.85, finish: EmblemFinish.Sheen, depth: EmblemDepth.Lifted)));

    /// A black stag on a field of gold.
    public static readonly SpaceHouse Storm = new("storm", "Storm", "CrestStorm", HouseLook(
        [Tincture.StormMidnight, Tincture.StormGunmetal, Tincture.StormBrass], SpaceThemeMode.Banner, SpaceBannerPattern.Quartered,
        Arms(EmblemBackplate.Hexagon, EmblemSymbol.Stag, EmblemTrim.DoubleLine, edgeWidth: 0.3,
            [Tincture.StormOr, Tincture.StormBrass, Tincture.StormSable, Tincture.StormSable, Tincture.StormSable,
                Tincture.StormSable])));

    /// A red dragon on black.
    public static readonly SpaceHouse Dragon = new("dragon", "Dragon", "CrestDragon", HouseLook(
        [Tincture.DragonChar, Tincture.DragonBlood, Tincture.DragonScarlet], SpaceThemeMode.Banner, SpaceBannerPattern.Bands,
        Arms(EmblemBackplate.Shield, EmblemSymbol.Dragon, EmblemTrim.Line, edgeWidth: 0.25,
            [Tincture.DragonSable, Tincture.DragonChar, Tincture.DragonFire, Tincture.DragonFire, Tincture.DragonFire,
                Tincture.DragonBlood],
            chargeScale: 1.25, depth: EmblemDepth.Lifted)));

    /// A golden rose on green, in a wreath of laurel.
    public static readonly SpaceHouse Meadow = new("meadow", "Meadow", "CrestMeadow", HouseLook(
        [Tincture.MeadowForest, Tincture.MeadowMoss, Tincture.MeadowWheat], SpaceThemeMode.Banner, SpaceBannerPattern.Lozenges,
        Arms(EmblemBackplate.Circle, EmblemSymbol.Rose, EmblemTrim.Laurel, edgeWidth: 0.25,
            [Tincture.MeadowVert, Tincture.MeadowMoss, Tincture.MeadowRose, Tincture.MeadowRose, Tincture.MeadowWheat,
                Tincture.MeadowForest])));

    /// A golden kraken on iron black, riveted round in gold.
    public static readonly SpaceHouse Iron = new("iron", "Iron", "CrestIron", HouseLook(
        [Tincture.IronBlack, Tincture.IronPewter, Tincture.IronPatina], SpaceThemeMode.Banner, SpaceBannerPattern.Stripes,
        Arms(EmblemBackplate.Octagon, EmblemSymbol.Kraken, EmblemTrim.Beaded, edgeWidth: 0.5,
            [Tincture.IronBlack, Tincture.IronPewter, Tincture.IronOr, Tincture.IronOr, Tincture.IronOr, Tincture.IronPatina],
            finish: EmblemFinish.Embossed)));

    /// A silver trout leaping over waves of blue and red.
    public static readonly SpaceHouse River = new("river", "River", "CrestRiver", HouseLook(
        [Tincture.RiverNavy, Tincture.RiverLapis, Tincture.RiverRust], SpaceThemeMode.Banner, SpaceBannerPattern.Split,
        Arms(EmblemBackplate.Banner, EmblemSymbol.Fish, EmblemTrim.Line, edgeWidth: 0.2,
            [Tincture.RiverAzure, Tincture.RiverGules, Tincture.RiverArgent, Tincture.RiverArgent, Tincture.RiverArgent,
                Tincture.RiverNavy],
            division: EmblemFieldDivision.Barry, divisionCount: 6)));

    /// A red sun on orange in a burst of gold, over Dorne's sands.
    public static readonly SpaceHouse Sun = new("sun", "Sun", "CrestSun", HouseLook(
        [Tincture.SunUmber, Tincture.SunTerracotta, Tincture.SunDune], SpaceThemeMode.Gradient, SpaceBannerPattern.Diagonal,
        Arms(EmblemBackplate.Circle, EmblemSymbol.Sun, EmblemTrim.Sunburst, edgeWidth: 0.25,
            [Tincture.SunTenne, Tincture.SunTerracotta, Tincture.SunOr, Tincture.SunGules, Tincture.SunOr, Tincture.SunUmber]),
        gradientAngle: 160));

    /// A pale raven on the black of the Watch, sealed in grey.
    public static readonly SpaceHouse Vigil = new("vigil", "Vigil", "CrestVigil", HouseLook(
        [Tincture.VigilOnyx, Tincture.VigilCharcoal, Tincture.VigilAsh], SpaceThemeMode.Banner, SpaceBannerPattern.Checkered,
        Arms(EmblemBackplate.Seal, EmblemSymbol.Raven, EmblemTrim.DoubleRing, edgeWidth: 0.45,
            [Tincture.VigilOnyx, Tincture.VigilCharcoal, Tincture.VigilAsh, Tincture.VigilBone, Tincture.VigilAsh,
                Tincture.VigilAsh],
            trimWeight: 0.9, depth: EmblemDepth.None)));

    public static IReadOnlyList<SpaceHouse> All { get; } = [Winter, Lion, Storm, Dragon, Meadow, Iron, River, Sun, Vigil];

    public string Name { get; }

    /// The house's name in the template gallery.
    [Localized]
    public string Title { get; }

    /// The look a Space starting from the house wears.
    public SpaceBranding Look { get; }

    /// The app icon in the house's colors, by its asset name.
    public string AppIconName { get; }

    #endregion

    #region Constructors

    private SpaceHouse(string name, string title, string appIconName, SpaceBranding look) {
        Name = name;
        Title = title;
        AppIconName = appIconName;
        Look = look;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceHouse? Named(string? name) => All.FirstOrDefault(house => house.Name == name);

    #endregion

    #region Actions - Looks

    /// A house's look: its sidebar colors in its own background, which keeps
    /// controls readable, and its arms.
    private static SpaceBranding HouseLook(Tincture[] colors, SpaceThemeMode mode, SpaceBannerPattern pattern, SpaceEmblem arms,
        double gradientAngle = 0) =>
        new(new([.. colors.Select(tincture => tincture.Color)]), pattern, BannerStrength: 1, ReadabilityFade: 0.45,
            KeepsControlsReadable: true, mode, gradientAngle, ShowsTexture: false, SpaceIconStyle.LayeredEmblem, SymbolColor: null,
            arms, EmblemVocabulary.Studio.Version, FolderColorIntensity: 0, SpaceTextColorMode.Automatic, HasCustomAppearance: false);

    /// A house's arms: its figure on its field, each part in a tincture of its
    /// own, `colors` holding the field, second field, band, emblem, border and
    /// edge.
    private static SpaceEmblem Arms(EmblemBackplate backplate, EmblemSymbol figure, EmblemTrim trim, double edgeWidth, Tincture[] colors,
        double chargeScale = 1.2, double trimWeight = 0.75, EmblemFinish? finish = null, EmblemDepth? depth = null,
        EmblemFieldDivision? division = null, int divisionCount = SpaceEmblem.DefaultDivisionCount) =>
        SpaceEmblem.PlainField(backplate, figure, trim, layers: [0, 1, 2, 4, 3, 5], trimWeight, chargeScale) with {
            FieldDivision = division ?? EmblemFieldDivision.Plain,
            DivisionCount = divisionCount,
            Palette = new([.. colors.Select(tincture => tincture.Color)]),
            EdgeWidth = edgeWidth,
            Finish = finish ?? EmblemFinish.Flat,
            Depth = depth ?? EmblemDepth.Soft
        };

    #endregion
}
