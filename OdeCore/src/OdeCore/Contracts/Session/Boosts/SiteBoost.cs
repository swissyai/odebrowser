namespace OdeCore.Contracts;

/// <summary>
/// How a person restyled one site's pages in a Space. <see cref="Site"/> is the
/// host the Boost applies to, as <see cref="SiteOf"/> spells it, and the Boost
/// applies only while <see cref="IsEnabled"/>. <see cref="IsDark"/> turns light
/// pages dark. A tint of <see cref="TintHue"/> degrees on the OKLCH hue circle
/// colors the page at <see cref="TintStrength"/>, from none at 0 to full at 1.
/// <see cref="Brightness"/> and <see cref="Contrast"/> leave the page as it is at
/// 1. <see cref="Font"/> sets its text, but code and icons, in one font, or
/// leaves the site's own for null. <see cref="HiddenSelectors"/> are the CSS
/// selectors of the elements the person hid, and <see cref="CustomCss"/> is CSS
/// the person wrote, applied after everything else.
/// </summary>
public sealed record SiteBoost(string Site, bool IsEnabled, bool IsDark, double TintHue, double TintStrength, double Brightness,
    double Contrast, BoostFont? Font, IReadOnlyList<string> HiddenSelectors, string CustomCss) {
    #region Static Variables

    public const int MaximumSiteLength = 253;
    public const int MaximumHiddenSelectors = 200;
    public const int MaximumSelectorLength = 512;
    public const int MaximumCustomCssLength = 65_536;
    /// The lowest and highest brightness and contrast a Boost sets.
    public const double MinimumLevel = 0.5;
    public const double MaximumLevel = 1.5;

    private const string WorldWideWebPrefix = "www.";

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<string> HiddenSelectors {
        get;
        init => field = [.. value];
    } = [.. HiddenSelectors];

    #endregion

    #region Actions - Sites

    /// The site a page at `host` belongs to: the host in lowercase, without a
    /// final dot, and without a leading "www." when a domain remains after it.
    /// Null for a host no Boost can name: empty, too long, or holding anything
    /// but letters, digits, dots, hyphens, underscores, or an address's colons
    /// and brackets.
    public static string? SiteOf(string? host) {
        if (host is null) return null;
        string site = host.Trim().ToLowerInvariant().TrimEnd('.');
        if (site.StartsWith(WorldWideWebPrefix, StringComparison.Ordinal) && site[WorldWideWebPrefix.Length..].Contains('.'))
            site = site[WorldWideWebPrefix.Length..];
        return site.Length is > 0 and <= MaximumSiteLength && site[0] != '.' && site.All(IsSiteCharacter) ? site : null;
    }

    private static bool IsSiteCharacter(char character) =>
        character is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '.' or '-' or '_' or ':' or '[' or ']';

    #endregion

    #region Actions - Normalization

    /// The Boost as a Space keeps it, or null when it names no site: its site
    /// spelled as `SiteOf` spells it, its hue within one turn, its strength
    /// within 0 through 1, its brightness and contrast within the levels a
    /// Boost sets, its hidden elements trimmed, each once, without a selector
    /// that could reach the rules after its own, and within their limits, and
    /// its CSS no longer than the limit.
    public SiteBoost? Normalized() {
        if (SiteOf(Site) is not { } site) return null;
        var selectors = HiddenSelectors.Select(selector => selector.Trim()).Where(IsContainedSelector)
            .Distinct(StringComparer.Ordinal).Take(MaximumHiddenSelectors).ToArray();
        string css = CustomCss.Length > MaximumCustomCssLength ? CustomCss[..MaximumCustomCssLength] : CustomCss;
        return this with {
            Site = site,
            TintHue = double.IsFinite(TintHue) ? (TintHue % 360 + 360) % 360 : 0,
            TintStrength = double.IsFinite(TintStrength) ? Math.Clamp(TintStrength, 0, 1) : 0,
            Brightness = Level(Brightness),
            Contrast = Level(Contrast),
            HiddenSelectors = selectors,
            CustomCss = css
        };
    }

    private static double Level(double value) => double.IsFinite(value) ? Math.Clamp(value, MinimumLevel, MaximumLevel) : 1;

    /// Whether `selector` stays within the one rule it is written into: not
    /// empty or too long, with no braces, comments or control characters, and
    /// with its escapes, brackets, parentheses and quotes closed.
    private static bool IsContainedSelector(string selector) {
        if (selector.Length is 0 or > MaximumSelectorLength || selector.Contains("/*", StringComparison.Ordinal)
            || selector.Any(character => character is '{' or '}' || char.IsControl(character))) return false;
        var open = new Stack<char>();
        char? quote = null;
        bool escaped = false;
        foreach (char character in selector) {
            if (escaped) {
                escaped = false;
            } else if (character == '\\') {
                escaped = true;
            } else if (quote is { } closing) {
                if (character == closing) quote = null;
            } else if (character is '"' or '\'') {
                quote = character;
            } else if (character is '[' or '(') {
                open.Push(character == '[' ? ']' : ')');
            } else if (character is ']' or ')') {
                if (open.Count == 0 || open.Pop() != character) return false;
            }
        }
        return !escaped && quote is null && open.Count == 0;
    }

    #endregion

    #region Actions - Equality

    public bool Equals(SiteBoost? other) => other is not null
        && Site == other.Site && IsEnabled == other.IsEnabled && IsDark == other.IsDark
        && TintHue.Equals(other.TintHue) && TintStrength.Equals(other.TintStrength)
        && Brightness.Equals(other.Brightness) && Contrast.Equals(other.Contrast) && Font == other.Font
        && HiddenSelectors.SequenceEqual(other.HiddenSelectors) && CustomCss == other.CustomCss;

    public override int GetHashCode() => HashCode.Combine(Site, IsEnabled, IsDark, HashCode.Combine(TintHue, TintStrength),
        HashCode.Combine(Brightness, Contrast), Font, HiddenSelectors.Count, CustomCss);

    #endregion
}
