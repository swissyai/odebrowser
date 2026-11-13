namespace OdeCore.Domain;

/// How well one typed term matches a row's text, by where it lands: at the
/// start of the title, at the start of a host label, at the start of a title
/// word, at the start of a path segment or a word within one, inside a title
/// word, inside a host label, or inside a path segment or anywhere in the
/// query string. A better match scores more points. Texts that are not a
/// page, such as a command, use only the title classes.
public sealed class TextMatch {
    #region Static Variables

    /// Inside a path segment, or anywhere in the query string.
    public static readonly TextMatch AddressInside = new(points: 150);
    /// Inside a host label.
    public static readonly TextMatch HostInside = new(points: 250);
    /// Inside a title word.
    public static readonly TextMatch Inside = new(points: 300);
    /// At the start of a path segment, or of a word within one.
    public static readonly TextMatch PathStart = new(points: 550);
    /// At the start of a title word.
    public static readonly TextMatch WordStart = new(points: 700);
    /// At the start of a host label other than the public suffix.
    public static readonly TextMatch HostLabelStart = new(points: 900);
    /// At the start of the title.
    public static readonly TextMatch TextStart = new(points: 1_000);

    #endregion

    #region Variables

    public int Points { get; }

    #endregion

    #region Constructors

    private TextMatch(int points) => Points = points;

    #endregion

    #region Actions - Comparison

    /// The better of two matches.
    public TextMatch Better(TextMatch other) => other.Points > Points ? other : this;

    #endregion
}
