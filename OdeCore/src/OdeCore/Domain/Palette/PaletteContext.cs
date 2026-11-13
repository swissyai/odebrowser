using OdeCore.Contracts;

namespace OdeCore.Domain;

/// Everything one answer of a window's palette reads, captured once: the
/// Space the window shows and the tab it shows there, whether the window is
/// private and its default engine opens internal pages, the device's palette
/// preferences and search catalog, what the Space searches with and whether
/// it suggests searches, what the Space's palette remembers, the workspace's
/// other Spaces, and the time. Each kind of result reads it to find its rows,
/// and each signal to score them. It reads only immutable records, so a
/// palette answers without holding the core's lock.
internal sealed class PaletteContext {
    #region Static Variables

    /// The fewest letters that let a row lead on a match that starts a word
    /// of its title or a segment of its path rather than the title or address.
    private const int MinimumWordLead = 3;

    #endregion

    #region Variables

    /// The Space the palette speaks for, or null when the window shows none
    /// the palette may read, as a locked one.
    public SpaceState? Space { get; }

    /// The tab the window shows, which the palette leaves out.
    public Guid? ShownTabId { get; }

    public bool IsPrivate { get; }
    public bool AllowsInternalPages { get; }
    public PalettePreferences Preferences { get; }
    public SearchCatalog Catalog { get; }

    /// What the Space searches with.
    public SearchProvider Search { get; }

    /// Whether the Space suggests searches as a person types.
    public bool Suggests { get; }

    public PaletteMemory Memory { get; }

    /// The workspace's other Spaces the palette may offer.
    public IReadOnlyList<SpaceState> Spaces { get; }

    public DateTimeOffset Now { get; }

    /// The device's time zone, which a time card compares others with.
    public TimeZoneInfo Zone { get; }

    /// The Space's history by address, or null without a Space.
    public AddressIndex? History { get; }

    /// The frecency of each host the Space knows, made on first use.
    private Dictionary<string, double>? hostFrecencies;

    #endregion

    #region Constructors

    public PaletteContext(SpaceState? space, Guid? shownTabId, bool isPrivate, bool allowsInternalPages, PalettePreferences preferences,
        SearchCatalog catalog, PaletteMemory memory, IReadOnlyList<SpaceState> spaces, DateTimeOffset now, TimeZoneInfo? zone = null) {
        Space = space;
        ShownTabId = shownTabId;
        IsPrivate = isPrivate;
        AllowsInternalPages = allowsInternalPages;
        Preferences = preferences;
        Catalog = catalog;
        Search = space is null ? catalog.DefaultFor(isPrivate) : catalog.For(space.Settings.BrowsingPreferences, isPrivate);
        Suggests = space is not null && catalog.SuggestsFor(space.Settings.BrowsingPreferences);
        Memory = memory;
        Spaces = spaces;
        Now = now;
        Zone = zone ?? TimeZoneInfo.Local;
        History = space is null ? null : AddressIndex.Of(space.History);
    }

    #endregion

    #region Actions - Evidence

    /// What ranking reads of a place whose text, its title and address taken
    /// apart, is `text`, for `query`: how well the text matches it by where
    /// each term lands and whether the match may lead, how much the page was
    /// used and typed, when its tab was, whether it is open or kept, and what
    /// earlier picks add. Null when the text matches nowhere, so a row is
    /// made only for a place that matches; with nothing typed, as when the
    /// person narrowed the palette to a kind, every place matches with no
    /// text points.
    public PaletteEvidence? Evidence(PaletteQuery query, PlaceText text, DateTimeOffset? lastUsed = null, bool isOpen = false,
        bool isKept = false, HistoryEntryState? entry = null) {
        bool prefixesTitle = query.PrefixesNormalized(text.Title);
        bool prefixesAddress = text.Address.Length > 0 && query.PrefixesNormalized(text.Address);
        PlaceMatch? match = query.IsEmpty ? new PlaceMatch(0, int.MaxValue, StartsHostLabel: false) : query.Score(text);
        if (match is null && !prefixesTitle && !prefixesAddress) return null;
        int score = prefixesTitle || prefixesAddress ? Math.Max(match?.Points ?? 0, TextMatch.TextStart.Points) : match!.Value.Points;
        bool leadsByText = prefixesTitle || prefixesAddress || match is { StartsHostLabel: true }
            || match is { } landed && landed.Points >= TextMatch.PathStart.Points && query.Text.Length >= MinimumWordLead;
        entry ??= text.NormalizedUrl is { } normalized ? History?.Entry(normalized) : null;
        double frecency = text.Url is null ? 0 : Memory.FrecencyOf(text.Place, entry, Now);
        var use = text.Place is { } place ? Memory.Places.GetValueOrDefault(place) : null;
        double learned = Preferences.LearnsChoices && text.Place is { } learnedPlace
            ? Memory.Learned(query.Text, new(PaletteDestinationKind.Address, learnedPlace), Now) : 0;
        return new(score, leadsByText, prefixesTitle, frecency, lastUsed, isOpen, isKept, learned, text,
            match?.Offset ?? int.MaxValue, text.IsHostOnly ? HostFrecency(text.Host) : 0, use?.TypedAt is not null, use?.TypedUses ?? 0,
            entry?.VisitCount ?? 0);
    }

    /// What ranking reads of a row that matched with `score` and is no
    /// place: only the match and what earlier picks add.
    public PaletteEvidence Matched(PaletteQuery query, PaletteRow row, int score) =>
        new(score, LeadsByText: false, PrefixesTitle: query.Prefixes(row.Title), Frecency: 0, LastUsed: null, IsOpen: false, IsKept: false,
            Learned(query, row), Text: null, Offset: int.MaxValue, HostFrecency: 0, Typed: false, TypedUses: 0, Visits: 0);

    /// The frecency of every page on `host` together: what the memory
    /// remembers of them, and for pages it does not, what the Space's history
    /// says. Summed once per answer.
    public double HostFrecency(string host) {
        if (hostFrecencies is null) {
            var hosts = Memory.HostFrecencies(Now);
            if (Space is { } space)
                foreach (var entry in space.History.Take(HistoryFinder.Scan)) {
                    var text = PlaceText.Of(entry);
                    if (text.Place is not { } place || Memory.Places.ContainsKey(place)) continue;
                    hosts[text.Host] = hosts.GetValueOrDefault(text.Host) + Memory.FrecencyOf(null, entry, Now);
                }
            hostFrecencies = hosts;
        }
        return hostFrecencies.GetValueOrDefault(host);
    }

    /// What the person's earlier picks for what was typed add to `row`.
    public double Learned(PaletteQuery query, PaletteRow row) =>
        Preferences.LearnsChoices && Destination(row) is { } destination ? Memory.Learned(query.Text, destination, Now) : 0;

    /// Where `row` leads, as picks remember it.
    public PaletteDestination? Destination(PaletteRow row) =>
        row.Kind.Destination(row, tab => Space?.Tabs.FirstOrDefault(candidate => candidate.Id == tab) is { } found
            ? found.SavedAddress ?? found.Url : null);

    #endregion

    #region Actions - Support

    /// The host `url` names, or null for none.
    public static string? Host(string? url) =>
        url is not null && Uri.TryCreate(url, UriKind.Absolute, out var parsed) && parsed.Host.Length > 0 ? parsed.Host : null;

    #endregion
}

/// What ranking reads of one row: how well the text matched it; whether the
/// match may lead, since the text starts its title, its address or a host
/// label, or from three letters a word of its title or a segment of its path;
/// whether it starts the title; how much its page was used; when its tab was
/// last used; whether it is open or kept; what the person's earlier picks
/// for the same text add; the page's text taken apart or null for a row that
/// is no page; where in the address the earliest term landed; for a site's
/// front page how much the whole site was used; whether and how often the
/// place was typed; and how often history saw it visited.
internal sealed record PaletteEvidence(int Match, bool LeadsByText, bool PrefixesTitle, double Frecency, DateTimeOffset? LastUsed, bool IsOpen,
    bool IsKept, double Learned, PlaceText? Text, int Offset, double HostFrecency, bool Typed, int TypedUses, int Visits);
