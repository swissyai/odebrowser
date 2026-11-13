using System.Runtime.CompilerServices;

using OdeCore.Contracts;

namespace OdeCore.Domain;

/// A page's title and address taken apart once for matching: the title as
/// ranking reads it, without a leading unread badge such as `(9+)` or
/// `(857)`, and its core without a trailing site name, the host in
/// lower case without `www.`, the host's labels before its public suffix,
/// the host without that suffix, the path's segments and the query string,
/// with the scheme and the fragment dropped, where each part starts in the
/// address, whether the address names only a host, and its place key. The
/// public suffix is taken as the last label, or the last two when the second
/// to last is three letters or fewer, as `co.uk`; a single label or an IP
/// address has none. Immutable, and kept beside the tab or history entry it
/// describes, which is immutable too, so every keystroke reads it instead of
/// taking the page apart again, from any thread.
public sealed class PlaceText {
    #region Static Variables

    /// What separates a title from the site name that follows it.
    private static readonly string[] SiteSeparators = [" - ", " – ", " — ", " | "];

    private static readonly ConditionalWeakTable<TabState, PlaceText> Tabs = [];
    private static readonly ConditionalWeakTable<HistoryEntryState, PlaceText> Entries = [];

    #endregion

    #region Variables

    /// The title as matching reads it: canonically normalized, without a
    /// leading unread badge. What the row shows is untouched.
    public string Title { get; }

    /// The title without a trailing site name, as "Safe" for "Safe - Site".
    public string Core { get; }

    /// The host in lower case without a leading `www.`, or empty for no address.
    public string Host { get; }

    /// The host without its public suffix, or the host when it has none.
    public string Name { get; }

    /// The host's labels before its public suffix.
    public IReadOnlyList<string> HostLabels { get; }

    /// Where each host label starts in `Address`.
    public IReadOnlyList<int> HostLabelOffsets { get; }

    /// The path's segments, unescaped.
    public IReadOnlyList<string> PathSegments { get; }

    /// Where each path segment starts in `Address`.
    public IReadOnlyList<int> PathSegmentOffsets { get; }

    /// The query string without its `?`, unescaped, or empty.
    public string Query { get; }

    /// Where the query starts in `Address`.
    public int QueryOffset { get; }

    /// The address as matching reads it: host, port, path and query.
    public string Address { get; }

    /// The address names a host and nothing more: no path and no query.
    public bool IsHostOnly { get; }

    /// The place key, or null for an address the palette does not remember.
    public string? Place { get; }

    /// The address as given, or null for none.
    public string? Url { get; }

    /// The address in the normal form history keys entries by, or null.
    public string? NormalizedUrl { get; }

    /// The host as the address spells it, with any `www.`, or null for none.
    public string? SpelledHost { get; }

    #endregion

    #region Constructors

    private PlaceText(string title, Uri? uri) {
        Title = WithoutBadge(TextFold.Normalized(title));
        Core = WithoutSite(Title);
        Url = uri?.OriginalString;
        Place = uri is null ? null : PaletteMemory.Place(uri.OriginalString);
        NormalizedUrl = Url is null ? null : new WebAddress(Url).Normalized;
        SpelledHost = uri is { Host.Length: > 0 } ? uri.Host : null;
        if (uri is null || uri.Host.Length == 0) {
            Host = "";
            Name = "";
            HostLabels = [];
            HostLabelOffsets = [];
            PathSegments = [];
            PathSegmentOffsets = [];
            Query = "";
            QueryOffset = 0;
            Address = "";
            IsHostOnly = false;
            return;
        }
        Host = PaletteMemory.WithoutWww(uri.Host.ToLowerInvariant());
        var labels = uri.HostNameType is UriHostNameType.IPv4 or UriHostNameType.IPv6 ? [Host] : Host.Split('.');
        int suffix = labels.Length switch {
            1 => 0,
            >= 3 when labels[^2].Length <= 3 => 2,
            _ => 1
        };
        Name = suffix == 0 ? Host : string.Join('.', labels[..^suffix]);
        List<string> hostLabels = [];
        List<int> hostOffsets = [];
        int offset = 0;
        for (int index = 0; index < labels.Length - suffix; index++) {
            hostLabels.Add(labels[index]);
            hostOffsets.Add(offset);
            offset += labels[index].Length + 1;
        }
        HostLabels = hostLabels;
        HostLabelOffsets = hostOffsets;
        string port = uri.IsDefaultPort ? "" : $":{uri.Port}";
        string path = uri.AbsolutePath == "/" ? "" : uri.AbsolutePath;
        List<string> segments = [];
        List<int> segmentOffsets = [];
        int start = Host.Length + port.Length;
        int position = 0;
        while (position < path.Length) {
            int next = path.IndexOf('/', position + 1);
            if (next < 0) next = path.Length;
            if (next > position + 1) {
                segments.Add(TextFold.Normalized(Uri.UnescapeDataString(path[(position + 1)..next])));
                segmentOffsets.Add(start + position + 1);
            }
            position = next;
        }
        PathSegments = segments;
        PathSegmentOffsets = segmentOffsets;
        Query = uri.Query.Length > 1 ? TextFold.Normalized(Uri.UnescapeDataString(uri.Query[1..])) : "";
        QueryOffset = start + path.Length + 1;
        Address = Host + port + path + uri.Query;
        IsHostOnly = path.Length == 0 && uri.Query.Length == 0;
    }

    /// The text of a page titled `title` at `url`, or with no address when
    /// `url` is null or is not one.
    public static PlaceText Of(string title, string? url) {
        ArgumentNullException.ThrowIfNull(title);
        return new(title, url is not null && Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri : null);
    }

    /// The text of `tab`: its shown title at the address it was saved at, or
    /// shows. Made once per tab record.
    public static PlaceText Of(TabState tab) {
        ArgumentNullException.ThrowIfNull(tab);
        return Tabs.GetValue(tab, made => Of(made.DisplayTitle, made.SavedAddress ?? made.Url));
    }

    /// The text of the history entry `entry`: its title, or its host when it
    /// has none, at its address. Made once per entry record.
    public static PlaceText Of(HistoryEntryState entry) {
        ArgumentNullException.ThrowIfNull(entry);
        return Entries.GetValue(entry, made => Of(made.Title.Length > 0 ? made.Title : PaletteContext.Host(made.Url) ?? made.Url, made.Url));
    }

    #endregion

    #region Actions - Support

    /// `title` without a leading unread badge: a count in parentheses, with
    /// or without a plus, followed by whitespace and the title itself.
    private static string WithoutBadge(string title) {
        if (title.Length < 4 || title[0] != '(') return title;
        int end = 1;
        while (end < title.Length && char.IsAsciiDigit(title[end])) end++;
        if (end == 1) return title;
        if (end < title.Length && title[end] == '+') end++;
        if (end >= title.Length || title[end] != ')') return title;
        string rest = title[(end + 1)..];
        string trimmed = rest.TrimStart();
        return trimmed.Length == 0 || trimmed.Length == rest.Length ? title : trimmed;
    }

    /// `title` without the site name after its last separator, when
    /// something precedes it.
    private static string WithoutSite(string title) {
        int cut = -1;
        foreach (var separator in SiteSeparators) cut = Math.Max(cut, title.LastIndexOf(separator, StringComparison.Ordinal));
        return cut > 0 ? title[..cut].TrimEnd() : title;
    }

    #endregion
}
