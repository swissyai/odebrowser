using System.Text.RegularExpressions;

using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The encyclopedia card a person may turn on: a short Wikipedia summary of
/// a topic whose exact name they typed, as "albert einstein" or "who is
/// albert einstein", with a picture only when Wikimedia Commons holds it
/// under a free licence and names its author. Titles that merely resemble
/// the text, which are often about something else, never show.
internal static partial class WebAnswer {
    #region Static Variables

    /// The fewest characters a topic needs before it is looked up.
    private const int MinimumTopic = 3;

    /// The longest topic looked up, and the most words in it.
    private const int MaximumTopic = 80;
    private const int MaximumWords = 6;

    /// The most of a summary a card shows.
    private const int MaximumExtract = 240;

    /// The licence Wikipedia's text is under, and where it is written.
    private const string TextLicense = "CC BY-SA 4.0";
    private const string TextLicenseAddress = "https://creativecommons.org/licenses/by-sa/4.0/";

    /// Where Commons, the free media library, keeps a file's page.
    private const string CommonsFilePage = "https://commons.wikimedia.org/wiki/File:";

    /// What Commons says about a file's author and licence, for `%s`, the
    /// file's name.
    private const string ImageInfoTemplate = "https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2"
        + "&prop=imageinfo&iiprop=extmetadata&iiextmetadatafilter=Artist%7CLicenseShortName&titles=File%3A%s";

    #endregion

    #region Actions - Asking

    /// The topic `text` names, without a leading "who is" or "what is" and a
    /// final question mark, or null when it is too short, too long or names
    /// no words.
    public static string? Topic(string text) {
        ArgumentNullException.ThrowIfNull(text);
        string collapsed = string.Join(' ', text.Trim().TrimEnd('?').Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        string topic = Asking().Replace(collapsed, "", 1).Trim();
        return topic.Length is >= MinimumTopic and <= MaximumTopic && topic.Any(char.IsLetter)
            && topic.Split(' ').Length <= MaximumWords ? topic : null;
    }

    /// Where the platform looks `topic` up on the Wikipedia `wikipedia`
    /// searches, such as `https://en.wikipedia.org/wiki/Special:Search?search=%s`.
    public static PaletteWebLookup Lookup(string topic, SearchProvider wikipedia) {
        ArgumentNullException.ThrowIfNull(topic);
        ArgumentNullException.ThrowIfNull(wikipedia);
        string host = Uri.TryCreate(wikipedia.SearchTemplate.Replace("%s", "", StringComparison.Ordinal), UriKind.Absolute, out var url)
            ? url.Host : "en.wikipedia.org";
        return new(topic, $"https://{host}/w/rest.php/v1/search/title?q={Uri.EscapeDataString(topic)}&limit=1",
            $"https://{host}/api/rest_v1/page/summary/%s", ImageInfoTemplate);
    }

    #endregion

    #region Actions - Answering

    /// The card for `summary`, which the platform fetched for `topic`, or
    /// null when its title is not the topic, it is no standard article, or it
    /// says nothing.
    public static PaletteCard? Card(PaletteWebSummary summary, string topic) {
        ArgumentNullException.ThrowIfNull(summary);
        ArgumentNullException.ThrowIfNull(topic);
        string extract = Shortened(summary.Extract);
        if (Folded(summary.Title) != Folded(topic) || summary.Type != "standard" || extract.Length == 0
            || !Uri.TryCreate(summary.Page, UriKind.Absolute, out var page) || page.Scheme != Uri.UriSchemeHttps)
            return null;
        return new(PaletteCardKind.Encyclopedia, summary.Title, summary.Description ?? "", extract, Value: null, summary.Page,
            Term: null, Clock: null, Image(summary), Credit: "Wikipedia", CreditAddress: summary.Page, TextLicense, TextLicenseAddress);
    }

    /// The summary's picture with its credit, only when Commons holds it, its
    /// licence is a free one and it names its author.
    private static PaletteCardImage? Image(PaletteWebSummary summary) {
        if (summary.Thumbnail is not { } thumbnail || !Uri.TryCreate(thumbnail, UriKind.Absolute, out var address)
            || address.Scheme != Uri.UriSchemeHttps || !address.AbsolutePath.Contains("/wikipedia/commons/", StringComparison.Ordinal)
            || CommonsFile(address) is not { } file || summary.ImageLicense is not { Length: > 0 } license
            || summary.ImageArtist is not { Length: > 0 } artist || !IsFree(license))
            return null;
        return new(thumbnail, $"Photo: {artist}, {license}", CommonsFilePage + Uri.EscapeDataString(file));
    }

    /// The name of the Commons file a picture address shows, whole or as a
    /// thumbnail, or null.
    public static string? CommonsFile(Uri address) {
        ArgumentNullException.ThrowIfNull(address);
        string[] parts = address.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        int commons = Array.IndexOf(parts, "commons");
        if (commons < 0) return null;
        int name = parts.Length > commons + 1 && parts[commons + 1] == "thumb" ? commons + 4 : commons + 3;
        return parts.Length > name ? Uri.UnescapeDataString(parts[name]) : null;
    }

    /// Whether a Commons licence name is a free one, as every licence Commons
    /// accepts should be, and not one that only allows fair use.
    private static bool IsFree(string license) {
        string lowered = license.ToLowerInvariant();
        return !lowered.Contains("fair use", StringComparison.Ordinal) && !lowered.Contains("non-free", StringComparison.Ordinal)
            && (lowered.StartsWith("cc", StringComparison.Ordinal) || lowered.Contains("public domain", StringComparison.Ordinal)
                || lowered.StartsWith("pd", StringComparison.Ordinal) || lowered.Contains("gfdl", StringComparison.Ordinal)
                || lowered.StartsWith("attribution", StringComparison.Ordinal) || lowered.Contains("free art", StringComparison.Ordinal));
    }

    /// The first sentences of `extract` that fit in `MaximumExtract`
    /// characters, or the start of the first cut at a word.
    private static string Shortened(string extract) {
        string collapsed = string.Join(' ', extract.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (collapsed.Length <= MaximumExtract) return collapsed;
        int end = -1;
        foreach (Match sentence in SentenceEnd().Matches(collapsed)) {
            if (sentence.Index + 1 > MaximumExtract) break;
            end = sentence.Index + 1;
        }
        if (end > 0) return collapsed[..end];
        int cut = collapsed.LastIndexOf(' ', MaximumExtract);
        return collapsed[..(cut > 0 ? cut : MaximumExtract)].TrimEnd(',', ';', ':') + "…";
    }

    /// `value` without case, diacritics or underscores, one space apart.
    private static string Folded(string value) =>
        string.Join(' ', TextFold.Folded(value.Replace('_', ' ')).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    [GeneratedRegex(@"^(?:who\s+(?:is|was|are|were)|what\s+(?:is|was|are|were)(?:\s+an?)?|where\s+is|tell\s+me\s+about)\s+",
        RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)]
    private static partial Regex Asking();

    [GeneratedRegex(@"[.!?](?=\s|$)", RegexOptions.CultureInvariant)]
    private static partial Regex SentenceEnd();

    #endregion
}
