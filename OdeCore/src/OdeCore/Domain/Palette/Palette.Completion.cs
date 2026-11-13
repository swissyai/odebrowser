using System.Runtime.CompilerServices;

using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The address or search the text itself runs, the search suggestions that
/// join it, and the address that completes it inline.
public sealed partial class Palette {
    #region Static Variables

    /// Each tab's addresses taken apart for completion, kept beside the tab
    /// record, which is immutable, so a keystroke reads them instead of
    /// taking every tab apart again.
    private static readonly ConditionalWeakTable<TabState, TabCandidates> Completions = [];

    #endregion

    #region Actions - Intent

    /// The rows the text runs: the address it opens, when it names one, then
    /// the search it runs with the Space's engine, or only that search when it
    /// names no address; none when nothing was typed or the text names nothing
    /// loadable. An address the Space knows under another spelling, such as
    /// with `www.`, opens the way the Space knows it, in the scheme the person
    /// typed when they typed one.
    private IReadOnlyList<PaletteRow> Intents(PaletteQuery query) {
        if (query.IsEmpty) return [];
        // A supported rewrite prefix such as “rewrite: ...” is typed text,
        // not a URL scheme. The private grammar already excludes addresses.
        if (Preferences.Offers(PaletteSource.AskOde) && GenerativeAnswerLookup.Of(query.Text) is not null)
            return [Searching(query.Text, context.Search.Search(query.Text))];
        AddressResolution? resolution;
        try {
            resolution = AddressResolution.Resolve(query.Text, context.Search, context.AllowsInternalPages);
        } catch (Rejected refused) when (refused.Rejection is UnsupportedAddress) {
            return [];
        }
        if (resolution is null || !Uri.TryCreate(resolution.Url, UriKind.Absolute, out var url)) return [];
        if (resolution.SearchQuery is { } searched) return [Searching(searched, resolution.Url)];
        bool typedScheme = Uri.TryCreate(query.Text, UriKind.Absolute, out var typed) && WebScheme.Named(typed.Scheme) is not null;
        string address = Known(resolution.Url, typedScheme ? url.Scheme : null) ?? resolution.Url;
        string host = url.Host.Length > 0 ? PaletteMemory.WithoutWww(url.Host) : resolution.Url;
        return [PaletteRow.Of(PaletteRowKind.OpenAddress, $"Open {host}", address, address: address),
            Searching(query.Text, context.Search.Search(query.Text))];
    }

    private PaletteRow Searching(string text, string address) =>
        Searching(PaletteRowKind.Search, context.Search.Kind.RowTitle(context.Search.Title), text, address, context.Search,
            TopResult.Address(context.Search, context.Catalog, text));

    /// The address the Space knows for the same place as `url`: an open or
    /// kept tab's, else history's; null when it knows none. Only an address
    /// in `scheme`, the one the person typed, is the same place when they
    /// typed one, so a typed `http://` never opens a known `https://` page.
    private string? Known(string url, string? scheme) {
        if (context.Space is not { } space || PaletteMemory.Place(url) is not { } place) return null;
        bool Same(string known) => PaletteMemory.Place(known) == place
            && (scheme is null || Uri.TryCreate(known, UriKind.Absolute, out var parsed) && parsed.Scheme == scheme);
        foreach (var tab in space.Tabs)
            if ((tab.SavedAddress ?? tab.Url) is { } known && Same(known)) return known;
        return space.History.Take(HistoryFinder.Scan).FirstOrDefault(entry => Same(entry.Url))?.Url;
    }

    private static PaletteRow Searching(PaletteRowKind kind, string title, string subtitle, string address, SearchProvider provider,
        string? topResult) =>
        PaletteRow.Of(kind, title, subtitle, address: address, provider: provider, topResult: topResult);

    #endregion

    #region Actions - Suggestions

    /// The fetched suggestions the shown rows and the typed text do not
    /// already say, each as a search with `provider`.
    private IReadOnlyList<PaletteRow> Suggestions(string text, IReadOnlyList<string> remote, IReadOnlyList<PaletteRow> shown,
        SearchProvider provider) {
        if (remote.Count == 0) return [];
        var claimed = new HashSet<string>(StringComparer.Ordinal) { TextFold.Folded(Collapsed(text)) };
        foreach (var row in shown) claimed.Add(TextFold.Folded(Collapsed(row.Title)));
        List<PaletteRow> rows = [];
        foreach (var fetched in remote) {
            if (rows.Count >= Preferences.Limit(PaletteSource.Suggestions)) break;
            string suggestion = Collapsed(fetched);
            if (suggestion.Length == 0 || suggestion.Length > MaximumSuggestionLength
                || !claimed.Add(TextFold.Folded(suggestion))) continue;
            rows.Add(Searching(PaletteRowKind.SearchSuggestion, suggestion, provider.Kind.RowTitle(provider.Title), provider.Search(suggestion),
                provider, TopResult.Address(provider, context.Catalog, suggestion)));
        }
        return rows;
    }

    private void AddSuggestions(List<PaletteGroup> groups, PaletteSuggestions question, IReadOnlyList<PaletteRow> shown, bool keepsPrivate) {
        if (keepsPrivate || !Preferences.Offers(PaletteSource.Suggestions)) return;
        var suggestions = Suggestions(question.Text, question.Remote, shown, context.Search);
        if (suggestions.Count > 0) groups.Add(new(PaletteSection.SearchSuggestions, suggestions));
    }

    /// Where to fetch suggestions for `text`, or null when this palette asks
    /// for none: in a private window, where the Space or the person turned
    /// them off, and for text it keeps to itself. `intent` is what the text
    /// itself runs, `lead` the local row that leads, if any, and `local` what
    /// the text asks the palette to work out.
    private string? SuggestionAddress(string text, PaletteRow? intent, PaletteCandidate? lead, LocalAnswer local,
        PaletteTranslationLookup? translation) {
        if (translation is not null || !Preferences.Offers(PaletteSource.Suggestions) || Withholds(text, intent, lead, local)) return null;
        return context.Search.Suggest(text);
    }

    /// Where to fetch the suggestions of `provider`, which the person entered,
    /// for `text`, or null when this palette asks for none.
    private string? ProviderSuggestionAddress(SearchProvider provider, string text) =>
        Withholds(text, intent: null, lead: null, local: null) || IsAddress(text) ? null : provider.Suggest(text);

    /// Whether the palette keeps `text` from every service it could ask while
    /// the person types: nothing was typed or too much was, the window is
    /// private, there is no Space or it suggests nothing, the text opens an
    /// address or names a scheme, a local match leads for it, it asks for
    /// arithmetic, or it looks like a secret. A written answer leading is no
    /// local match, since a question may still be a search. `local` is what
    /// the text asks the palette to work out, when it was read already.
    private bool Withholds(string text, PaletteRow? intent, PaletteCandidate? lead, LocalAnswer? local) {
        string trimmed = text.Trim();
        return trimmed.Length == 0 || trimmed.Length > MaximumSuggestionLength || context.IsPrivate || context.Space is null
            || !context.Suggests || intent?.Kind == PaletteRowKind.OpenAddress || NamesScheme(trimmed)
            || lead is not null && lead.Source != PaletteSource.Answers || SecretText.Looks(trimmed)
            || (local is null ? LocalAnswer.Arithmetic(context, trimmed) : local.Calculation) is not null;
    }

    /// Whether `text` opens an address rather than searching, with what the
    /// Space searches with.
    private bool IsAddress(string text) {
        try {
            return AddressResolution.Resolve(text, context.Search, context.AllowsInternalPages) is { SearchQuery: null };
        } catch (Rejected refused) when (refused.Rejection is UnsupportedAddress) {
            return true;
        }
    }

    /// Whether `text` starts with a scheme, such as `https:` or `file:`.
    private static bool NamesScheme(string text) {
        int colon = text.IndexOf(':', StringComparison.Ordinal);
        return colon > 0 && !text[..colon].Contains(' ', StringComparison.Ordinal)
            && Uri.TryCreate(text, UriKind.Absolute, out var url) && url.Scheme.Length == colon;
    }

    /// The words of `value`, one space apart.
    private static string Collapsed(string value) =>
        string.Join(' ', value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    #endregion

    #region Actions - Completion

    /// The address the Space knows that best completes the text, as other
    /// browsers complete it: the host whole, without a `www.` nobody typed,
    /// up to the next `/` once a path is typed, and only for places a person
    /// typed or picked within the lifetime, a tab shows or keeps, or history
    /// visited at least four times before the Space began remembering. Null
    /// when none does, when one is exactly what was typed, or when the field
    /// may not complete now.
    private AddressMatch? Completion(PaletteSuggestions question) {
        if (context.Space is null || !question.AllowsCompletion || !Preferences.CompletesInline
            || TypedAddress.Of(question.Text) is not { } typed)
            return null;
        AddressMatch? best = null;
        double Use(AddressCandidate candidate) {
            double remembered = context.Memory.Frecency(candidate.Url, null, context.Now);
            return remembered > 0 ? remembered
                : candidate.Visits * Math.Pow(2, -(context.Now - candidate.Date).TotalDays / PaletteMemory.HalfLifeDays);
        }
        foreach (var candidate in CompletionCandidates()) {
            if (!Completes(candidate) || candidate.Completing(typed) is not { } match) continue;
            if (string.Equals(match.Text, typed.Text, StringComparison.OrdinalIgnoreCase)) return null;
            if (best is null || match.Outranks(best, Use)) best = match;
        }
        return best is null || best.Text.Length <= typed.Text.Length ? null : best;
    }

    /// What accepting `match` leaves in the field: its text, with the scheme
    /// when the address is not https.
    private static string Accepted(AddressMatch match) =>
        match.Text.Contains("://", StringComparison.Ordinal) || match.Candidate.Scheme == WebScheme.Https.Name
            ? match.Text : $"{match.Candidate.Scheme}://{match.Text}";

    /// Whether `candidate` may complete inline: a tab's address always, and
    /// a history address the person typed or used heavily before memory began.
    private bool Completes(AddressCandidate candidate) {
        if (candidate.Source != AddressCandidate.HistorySource) return true;
        if (context.Memory.WasTyped(candidate.Authority, context.Now)) return true;
        return candidate.Visits >= 4 && candidate.FirstVisited is { } first && first < context.Memory.Since;
    }

    private IEnumerable<AddressCandidate> CompletionCandidates() {
        foreach (var tab in context.Space!.Tabs.Where(tab => !tab.IsStartPage)) {
            var candidates = Completions.GetValue(tab, TabCandidates.Of);
            if (candidates.Shown is { } shown) yield return shown;
            if (candidates.Kept is { } kept) yield return kept;
        }
        foreach (var candidate in context.History!.Candidates()) yield return candidate;
    }

    #endregion

    #region Types

    /// A tab's addresses as completion reads them: the page it shows, and the
    /// one it was saved at when it is kept.
    private sealed record TabCandidates(AddressCandidate? Shown, AddressCandidate? Kept) {
        public static TabCandidates Of(TabState tab) {
            int source = tab.Placement.IsDurable ? AddressCandidate.SavedTabSource : AddressCandidate.OpenTabSource;
            return new(tab.Url is { } url ? AddressCandidate.Of(url, source, tab.LastActivatedAt, visits: 0) : null,
                tab.SavedAddress is { } saved ? AddressCandidate.Of(saved, AddressCandidate.SavedTabSource, tab.LastActivatedAt, visits: 0) : null);
        }
    }

    #endregion
}
