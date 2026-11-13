using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// How the palette tells rows apart once they score alike, which row stays
/// when several name one page, and how many rows a host may fill: the ladder
/// runs typed, nearest match, typed count, front page, visits, last use, then
/// title; an open tab beats a kept tab beats history at one place; history
/// collapses on host and title and gives at most three rows per host unless
/// the palette is narrowed to it; a completion to a bare host switches to the
/// strongest tab on it; and a word or path match leads from three letters.
public sealed class PaletteOrderTests {
    #region Static Variables

    private static readonly DateTimeOffset Now = new(2026, 11, 8, 12, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Ladder

    [Fact]
    public void ATypedPlaceOutranksOneOnlyVisited() {
        const string typed = "https://docs.example/alpha", visited = "https://docs.example/beta";
        var memory = PaletteMemory.Starting(Now.AddDays(-1))
            .Chose("do", PaletteDestination.Address(typed)!, typed, null, Now.AddHours(-2), learns: false).Visited(typed, null, Now.AddHours(-2))
            .Visited(visited, null, Now.AddHours(-2)).Visited(visited, null, Now.AddHours(-2));

        Assert.Equal([typed, visited], History(Space(History: [(visited, "Guide A", 1), (typed, "Guide Z", 1)]), "guide", memory));
    }

    [Fact]
    public void TheMatchNearestTheStartOfTheAddressWins() {
        var space = Space(History: [("https://docs.example/x/guide", "Notes A", 1), ("https://docs.example/guide", "Notes Z", 1)]);

        Assert.Equal(["https://docs.example/guide", "https://docs.example/x/guide"], History(space, "guide"));
    }

    [Fact]
    public void MoreTypedUsesWinAmongTypedPlaces() {
        const string twice = "https://docs.example/alpha", once = "https://docs.example/beta";
        var memory = PaletteMemory.Starting(Now.AddDays(-1))
            .Chose("do", PaletteDestination.Address(twice)!, twice, null, Now.AddHours(-2), learns: false)
            .Chose("do", PaletteDestination.Address(twice)!, twice, null, Now.AddHours(-2), learns: false)
            .Chose("do", PaletteDestination.Address(once)!, once, null, Now.AddHours(-2), learns: false).Visited(once, null, Now.AddHours(-2));

        Assert.Equal([twice, once], History(Space(History: [(once, "Guide A", 1), (twice, "Guide Z", 1)]), "guide", memory));
    }

    [Fact]
    public void ASitesFrontPageOutranksADeeperPageThatScoresAlike() {
        var space = Space(Saved: [("https://alpha.example/deep", "Deep"), ("https://alpha.example/", "Root")]);

        Assert.Equal(["https://alpha.example/", "https://alpha.example/deep"], Saved(space, "alph"));
    }

    [Fact]
    public void MoreVisitsWinWhenFrecencyTies() {
        var space = Space(History: [("https://docs.example/a", "Guide A", 2, 0), ("https://docs.example/b", "Guide Z", 4, 30)]);

        Assert.Equal(["https://docs.example/b", "https://docs.example/a"], History(space, "guide"));
    }

    [Fact]
    public void TheLaterUseWinsAndThenTheTitle() {
        var space = Space(Saved: [("https://stake.example/address/1", "Stake Analytics", 400), ("https://stake.example/address/2", "Stake Analytics", 300),
            ("https://stake.example/address/3", "Beta Stake", 300), ("https://stake.example/address/4", "Alpha Stake", 300)]);

        Assert.Equal(["https://stake.example/address/2", "https://stake.example/address/1"], Saved(space, "stake analytics"));
        Assert.Equal(["https://stake.example/address/4", "https://stake.example/address/3"],
            Saved(space, "stake").Where(url => url.EndsWith('3') || url.EndsWith('4')));
    }

    #endregion

    #region Actions - Duplicates

    [Fact]
    public void OnePlaceShowsOnceAsItsStrongestKind() {
        var space = Space(Open: [("https://notes.example/page#top", "Notes")],
            Saved: [("http://www.notes.example/page", "Notes"), ("https://notes.example/page", "Notes")],
            History: [("https://notes.example/page", "Notes", 3)]);

        var rows = Rows(space, "notes");
        var place = Assert.Single(rows, row => row.TabId is not null || row.Kind == PaletteRowKind.History);
        Assert.Equal(PaletteRowKind.Tab, place.Kind);
    }

    [Theory]
    [InlineData("http://www.example.org/a#frag", "https://example.org/a", true)]
    [InlineData("https://example.org/a?q=1", "https://example.org/a", false)]
    [InlineData("https://example.org:8443/a", "https://example.org/a", false)]
    public void ThePlaceKeyDropsSchemeWwwAndFragmentAndKeepsTheQuery(string left, string right, bool same) =>
        Assert.Equal(same, PaletteMemory.Place(left) == PaletteMemory.Place(right));

    [Fact]
    public void HistoryRowsThatShareAHostAndTitleCollapseIntoTheStrongestOrTheTab() {
        var space = Space(Saved: [("https://ferrite.example/?ref=design", "Ferrite Computer Company")],
            History: [("https://ferrite.example/", "Ferrite Computer Company", 2), ("https://sage.example/chat/1", "Plan the week - Sage", 1),
                ("https://sage.example/chat/2", "Plan the week - Sage", 3), ("https://sage.example/chat/3", "Fix the build - Sage", 1)]);

        var rows = Rows(space, "ferrite");
        Assert.Single(rows, row => row.TabId is not null);
        Assert.DoesNotContain(rows, row => row.Kind == PaletteRowKind.History);
        Assert.Equal(["https://sage.example/chat/2", "https://sage.example/chat/3"], History(space, "sage"));
    }

    [Fact]
    public void AHostFillsAtMostThreeHistoryRowsUnlessThePaletteIsNarrowedToHistory() {
        var space = Space(History: [.. Enumerable.Range(1, 5).Select(n => ($"https://dash.example/page{n}", $"Page {n} - Dash", n))]);

        Assert.Equal(3, History(space, "dash").Count);
        var narrowed = Answer(space, "dash", scope: PaletteScope.History).Groups.Single().Rows;
        Assert.Equal(5, narrowed.Count);
    }

    #endregion

    #region Actions - Leading

    [Fact]
    public void ACompletionToABareHostSwitchesToTheStrongestTabOnIt() {
        var space = Space(Saved: [("https://patterns.example/changelog", "Changelog | Patterns")]);

        var answer = Answer(space, "patte");

        Assert.Equal(new AddressCompletion("patte", "rns.example", "patterns.example"), answer.Completion);
        var lead = answer.Groups[0];
        Assert.Equal(PaletteSection.TopHit, lead.Section);
        Assert.Equal((space.Tabs[0].Id, PaletteReason.Completion), (lead.Rows[0].TabId, lead.Rows[0].Reason));
    }

    [Fact]
    public void AWordOrPathMatchLeadsFromThreeLettersWhileATwoLetterOneNeedsThePrefix() {
        var space = Space(Saved: [("https://docs.example/d/1", "441m Staking Issuance - Docs"), ("https://codehub.example/avery/QuickLedger/pull/73", "Integrate auth")]);

        Assert.Equal(space.Tabs[0].Id, Answer(space, "staking").Groups[0].Rows[0].TabId);
        Assert.Equal(space.Tabs[1].Id, Answer(space, "quickledger").Groups[0].Rows[0].TabId);
        Assert.NotEqual(PaletteSection.TopHit, Answer(space, "st").Groups[0].Section);
    }

    [Fact]
    public void OneExactPickIsWorthSixHundredAndAPrefixPickAtLeastHalf() {
        const string page = "https://calendar.example/week";
        var memory = PaletteMemory.Starting(Now.AddDays(-1)).Chose("calendar", PaletteDestination.Address(page)!, page, null, Now, learns: true);

        Assert.Equal(600, memory.Learned("calendar", PaletteDestination.Address(page)!, Now), 6);
        Assert.Equal(150, memory.Learned("ca", PaletteDestination.Address(page)!, Now), 6);
    }

    #endregion

    #region Actions - Support

    private static IReadOnlyList<string> History(SpaceState space, string text, PaletteMemory? memory = null) =>
        [.. Rows(space, text, memory).Where(row => row.Kind == PaletteRowKind.History).Select(row => row.Address!)];

    private static IEnumerable<string> Saved(SpaceState space, string text) =>
        Rows(space, text).Where(row => row.TabId is not null).Select(row => space.Tabs.Single(tab => tab.Id == row.TabId).SavedAddress!);

    private static List<PaletteRow> Rows(SpaceState space, string text, PaletteMemory? memory = null) =>
        [.. Answer(space, text, memory).Groups.SelectMany(group => group.Rows)];

    private static PaletteAnswer Answer(SpaceState space, string text, PaletteMemory? memory = null, PaletteScope? scope = null) {
        var palette = new Palette(space, shownTabId: null, isPrivate: false, allowsInternalPages: true, AppPreferences.Default,
            SearchCatalog.Starting(language: null, region: null), memory ?? PaletteMemory.Starting(Now.AddDays(1)), [], Now);
        return palette.Answer(new PaletteSuggestions(Guid.NewGuid(), text, [], [], [], Provider: null, scope, AllowsCompletion: true, Pasteboard: null));
    }

    /// A Space with open tabs, saved tabs last used `DaysAgo` days ago (a
    /// week by default) and history entries visited `Visits` times, last
    /// `DaysAgo` days ago (today by default).
    private static SpaceState Space(IReadOnlyList<(string Url, string Title)>? Open = null,
        IReadOnlyList<(string Url, string Title, int DaysAgo)>? Saved = null,
        IReadOnlyList<(string Url, string Title, int Visits, int DaysAgo)>? History = null) {
        JsonArray tabs = [];
        foreach (var (url, title) in Open ?? [])
            tabs.Add(Tab(url, title, "current", Now.AddDays(-7)));
        foreach (var (url, title, daysAgo) in Saved ?? [])
            tabs.Add(Tab(url, title, "saved", Now.AddDays(-daysAgo)));
        var history = (History ?? []).Select(entry => (JsonNode)new JsonObject {
            ["id"] = Guid.NewGuid().ToString("D"),
            ["url"] = entry.Url,
            ["title"] = entry.Title,
            ["firstVisitedAt"] = StoredSessionCodec.Seconds(Now.AddDays(-entry.DaysAgo - 1)),
            ["lastVisitedAt"] = StoredSessionCodec.Seconds(Now.AddDays(-entry.DaysAgo)),
            ["visitCount"] = entry.Visits
        });
        return StoredSessionCodec.DecodeSpace(new JsonObject {
            ["id"] = new JsonObject { ["rawValue"] = Guid.NewGuid().ToString("D") },
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString("D") },
            ["name"] = "Reading",
            ["tabs"] = tabs,
            ["history"] = new JsonArray([.. history])
        });
    }

    private static SpaceState Space(IReadOnlyList<(string Url, string Title)>? Open = null, IReadOnlyList<(string Url, string Title)>? Saved = null,
        IReadOnlyList<(string Url, string Title, int Visits)>? History = null) =>
        Space(Open, Saved?.Select(tab => (tab.Url, tab.Title, 7)).ToList(), History?.Select(entry => (entry.Url, entry.Title, entry.Visits, 0)).ToList());

    private static JsonObject Tab(string url, string title, string placement, DateTimeOffset lastActivated) => new() {
        ["id"] = new JsonObject { ["rawValue"] = Guid.NewGuid().ToString("D") },
        ["title"] = title,
        ["url"] = url,
        ["savedURL"] = url,
        ["placement"] = placement,
        ["symbol"] = "globe",
        ["lastActivatedAt"] = StoredSessionCodec.Seconds(lastActivated)
    };

    #endregion
}
