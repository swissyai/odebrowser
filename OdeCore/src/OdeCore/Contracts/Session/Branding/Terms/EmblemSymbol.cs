namespace OdeCore.Contracts;

/// A heraldic figure a emblem can carry: its bundled artwork when it has any,
/// else the system glyph that draws it.
public sealed class EmblemSymbol {
    #region Variables

    // The Beetle draws the ladybug glyph and is named for it; Oak draws Leaf's
    // glyph, so it stays readable but isn't offered.
    public static readonly EmblemSymbol Dragon = new("dragon", "Dragon", EmblemVocabulary.Studio, "flame.fill", "EmblemCharge-dragon");
    public static readonly EmblemSymbol Direwolf = new("direwolf", "Direwolf", EmblemVocabulary.Studio, "dog.fill", "EmblemCharge-direwolf");
    public static readonly EmblemSymbol Lion = new("lion", "Lion", EmblemVocabulary.Studio, "pawprint.fill", "EmblemCharge-lion");
    public static readonly EmblemSymbol Stag = new("stag", "Stag", EmblemVocabulary.Studio, "leaf.fill", "EmblemCharge-stag");
    public static readonly EmblemSymbol Raven = new("raven", "Raven", EmblemVocabulary.Studio, "bird.fill", "EmblemCharge-raven");
    public static readonly EmblemSymbol Griffin = new("griffin", "Griffin", EmblemVocabulary.Studio, "bird.fill", "EmblemCharge-griffin");
    public static readonly EmblemSymbol Eagle = new("eagle", "Eagle", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-eagle");
    public static readonly EmblemSymbol Bear = new("bear", "Bear", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-bear");
    public static readonly EmblemSymbol Boar = new("boar", "Boar", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-boar");
    public static readonly EmblemSymbol Fox = new("fox", "Fox", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-fox");
    public static readonly EmblemSymbol Horse = new("horse", "Horse", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-horse");
    public static readonly EmblemSymbol Unicorn = new("unicorn", "Unicorn", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-unicorn");
    public static readonly EmblemSymbol Wyvern = new("wyvern", "Wyvern", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-wyvern");
    public static readonly EmblemSymbol Hydra = new("hydra", "Hydra", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-hydra");
    public static readonly EmblemSymbol Serpent = new("serpent", "Serpent", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-serpent");
    public static readonly EmblemSymbol Kraken = new("kraken", "Kraken", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-kraken");
    public static readonly EmblemSymbol Seahorse = new("seahorse", "Seahorse", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-seahorse");
    public static readonly EmblemSymbol Scorpion = new("scorpion", "Scorpion", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-scorpion");
    public static readonly EmblemSymbol Bat = new("bat", "Bat", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-bat");
    public static readonly EmblemSymbol Falcon = new("falcon", "Falcon", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-falcon");
    public static readonly EmblemSymbol Rose = new("rose", "Rose", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-rose");
    public static readonly EmblemSymbol Lily = new("lily", "Fleur-de-lis", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-lily");
    public static readonly EmblemSymbol Pine = new("pine", "Pine", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-pine");
    public static readonly EmblemSymbol Willow = new("willow", "Willow", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-willow");
    public static readonly EmblemSymbol Swords = new("swords", "Crossed Swords", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-swords");
    public static readonly EmblemSymbol Axes = new("axes", "Crossed Axes", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-axes");
    public static readonly EmblemSymbol Sword = new("sword", "Sword", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-sword");
    public static readonly EmblemSymbol Trident = new("trident", "Trident", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-trident");
    public static readonly EmblemSymbol Anchor = new("anchor", "Anchor", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-anchor");
    public static readonly EmblemSymbol Castle = new("castle", "Castle", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-castle");
    public static readonly EmblemSymbol Scales = new("scales", "Scales", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-scales");
    public static readonly EmblemSymbol DragonHead = new("dragonHead", "Dragon Head", EmblemVocabulary.Studio, "shield.fill", "EmblemCharge-dragonHead");
    public static readonly EmblemSymbol Hound = new("hound", "Hound", EmblemVocabulary.ExpandedCharges, "dog.fill", null);
    public static readonly EmblemSymbol Paw = new("paw", "Paw", EmblemVocabulary.ExpandedCharges, "pawprint.fill", null);
    public static readonly EmblemSymbol Hare = new("hare", "Hare", EmblemVocabulary.Baseline, "hare.fill", null);
    public static readonly EmblemSymbol Bird = new("bird", "Bird", EmblemVocabulary.Baseline, "bird.fill", null);
    public static readonly EmblemSymbol Fish = new("fish", "Fish", EmblemVocabulary.Baseline, "fish.fill", null);
    public static readonly EmblemSymbol Bee = new("bee", "Beetle", EmblemVocabulary.Baseline, "ladybug.fill", null);
    public static readonly EmblemSymbol Shell = new("shell", "Shell", EmblemVocabulary.Baseline, "fossil.shell.fill", null);
    public static readonly EmblemSymbol Sun = new("sun", "Sun", EmblemVocabulary.Baseline, "sun.max.fill", null);
    public static readonly EmblemSymbol RisingSun = new("risingSun", "Rising Sun", EmblemVocabulary.ExpandedCharges, "sun.horizon.fill", null);
    public static readonly EmblemSymbol Crescent = new("crescent", "Crescent", EmblemVocabulary.Baseline, "moon.fill", null);
    public static readonly EmblemSymbol Star = new("star", "Star", EmblemVocabulary.Baseline, "star.fill", null);
    public static readonly EmblemSymbol Sparkles = new("sparkles", "Sparkles", EmblemVocabulary.Baseline, "sparkles", null);
    public static readonly EmblemSymbol Lightning = new("lightning", "Lightning", EmblemVocabulary.Baseline, "bolt.fill", null);
    public static readonly EmblemSymbol Flame = new("flame", "Flame", EmblemVocabulary.Baseline, "flame.fill", null);
    public static readonly EmblemSymbol Snowflake = new("snowflake", "Snowflake", EmblemVocabulary.ExpandedCharges, "snowflake", null);
    public static readonly EmblemSymbol Drop = new("drop", "Drop", EmblemVocabulary.ExpandedCharges, "drop.fill", null);
    public static readonly EmblemSymbol Mountain = new("mountain", "Mountain", EmblemVocabulary.Baseline, "mountain.2.fill", null);
    public static readonly EmblemSymbol Tree = new("tree", "Tree", EmblemVocabulary.Baseline, "tree.fill", null);
    public static readonly EmblemSymbol Oak = new("oak", "Oak", EmblemVocabulary.Baseline, "leaf.fill", null, isOffered: false);
    public static readonly EmblemSymbol Leaf = new("leaf", "Leaf", EmblemVocabulary.Baseline, "leaf.fill", null);
    public static readonly EmblemSymbol Fern = new("fern", "Frond", EmblemVocabulary.Baseline, "laurel.leading", null);
    public static readonly EmblemSymbol Flower = new("flower", "Flower", EmblemVocabulary.ExpandedCharges, "camera.macro", null);
    public static readonly EmblemSymbol Waves = new("waves", "Waves", EmblemVocabulary.Baseline, "water.waves", null);
    public static readonly EmblemSymbol Tower = new("tower", "Tower", EmblemVocabulary.Baseline, "building.columns.fill", null);
    public static readonly EmblemSymbol Book = new("book", "Book", EmblemVocabulary.Baseline, "book.closed.fill", null);
    public static readonly EmblemSymbol Key = new("key", "Key", EmblemVocabulary.Baseline, "key.fill", null);
    public static readonly EmblemSymbol Hammer = new("hammer", "Hammer", EmblemVocabulary.Baseline, "hammer.fill", null);
    public static readonly EmblemSymbol Compass = new("compass", "Compass", EmblemVocabulary.Baseline, "location.north.circle.fill", null);
    public static readonly EmblemSymbol Sailboat = new("sailboat", "Sailboat", EmblemVocabulary.Baseline, "sailboat.fill", null);
    public static readonly EmblemSymbol Crown = new("crown", "Crown", EmblemVocabulary.ExpandedCharges, "crown.fill", null);
    public static readonly EmblemSymbol Horn = new("horn", "Horn", EmblemVocabulary.ExpandedCharges, "horn.fill", null);
    public static readonly EmblemSymbol CrossedBanners = new("crossedBanners", "Banners", EmblemVocabulary.ExpandedCharges, "flag.2.crossed.fill", null);

    public static IReadOnlyList<EmblemSymbol> All { get; } = [
        Dragon, Direwolf, Lion, Stag, Raven, Griffin, Eagle, Bear, Boar, Fox, Horse, Unicorn, Wyvern, Hydra, Serpent,
        Kraken, Seahorse, Scorpion, Bat, Falcon, Rose, Lily, Pine, Willow, Swords, Axes, Sword, Trident, Anchor, Castle,
        Scales, DragonHead, Hound, Paw, Hare, Bird, Fish, Bee, Shell, Sun, RisingSun, Crescent, Star, Sparkles, Lightning,
        Flame, Snowflake, Drop, Mountain, Tree, Oak, Leaf, Fern, Flower, Waves, Tower, Book, Key, Hammer, Compass, Sailboat,
        Crown, Horn, CrossedBanners
    ];

    /// The figure a emblem draws when it names none this build can read.
    public static EmblemSymbol Fallback => Mountain;

    public string Name { get; }

    /// The figure's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the figure.
    public EmblemVocabulary DrawnSince { get; }

    /// The system glyph that draws the figure where it has no artwork.
    public string SystemImage { get; }

    /// The bundled artwork that draws the figure, if it has any.
    public string? AssetName { get; }

    /// Whether the gallery offers the figure.
    public bool IsOffered { get; }

    #endregion

    #region Constructors

    private EmblemSymbol(string name, string title, EmblemVocabulary drawnSince, string systemImage, string? assetName,
        bool isOffered = true) {
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        SystemImage = systemImage;
        AssetName = assetName;
        IsOffered = isOffered;
    }

    #endregion

    #region Actions - Lookup

    public static EmblemSymbol? Named(string? name) => All.FirstOrDefault(symbol => symbol.Name == name);

    #endregion
}
