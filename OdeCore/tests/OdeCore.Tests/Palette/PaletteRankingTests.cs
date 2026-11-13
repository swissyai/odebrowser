using System.Globalization;
using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// How the palette decides what leads and in what order: inline completion
/// follows other browsers and Return opens what the field shows, a place shows
/// once as its strongest kind, picks for the same text lead and can be
/// forgotten, a private window remembers nothing, site searches answer only
/// to their exact shortcut and search only their site, and what the palette
/// remembers survives the device store.
public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("cafe\u0301", "Café notes")]
    [InlineData("café", "Cafe\u0301 notes")]
    public void ATabsQueryRefindsCanonicalTitlesWithoutChangingTheirDisplayOrSearchText(string typed, string title) {
        var (target, shown) = (Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(target, title, "https://notes.example.org/"),
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")]);
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));

        var tabs = device.Query(Asking(window, typed) with { Scope = PaletteScope.Tabs });
        var row = Assert.Single(Assert.Single(tabs.Groups).Rows);

        Assert.Equal((target, title), (row.TabId, row.Title));
        var search = device.Query(Asking(window, typed) with { AllowsCompletion = false }).Groups
            .SelectMany(group => group.Rows).Single(result => result.Kind == PaletteRowKind.Search);
        Assert.Equal(typed, search.Subtitle);
        Assert.Contains(Uri.EscapeDataString(typed), search.Address!);
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public void ARejectedTabTitleCannotPreventFindingOtherTabs(bool tabsOnly, bool rejectedFirst) {
        var (clean, rejected, shown) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        const string title = "\uFFFE cafe\u0301 garden plan";
        const string address = "https://uvw.test/two";
        var cleanTab = OpenTab(clean, "Clean target", "https://xyz.test/one");
        var rejectedTab = OpenTab(rejected, title, address);
        var (session, space) = PaletteSession(rejectedFirst
            ? [rejectedTab, cleanTab, OpenTab(shown, "Elsewhere", "https://elsewhere.test/")]
            : [cleanTab, rejectedTab, OpenTab(shown, "Elsewhere", "https://elsewhere.test/")]);
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));
        var scope = tabsOnly ? PaletteScope.Tabs : null;

        var answer = device.Query(Asking(window, "clean") with { Scope = scope });

        var cleanRow = Assert.Single(answer.Groups.SelectMany(group => group.Rows), row => row.TabId == clean);
        Assert.Equal("Clean target", cleanRow.Title);
        var rejectedRow = Assert.Single(device.Query(Asking(window, "café") with { Scope = scope }).Groups
            .SelectMany(group => group.Rows), row => row.TabId == rejected);
        Assert.Equal(title, rejectedRow.Title);
        device.Send(new ShowTab(window, space, rejectedRow.TabId));
        Assert.Equal(rejected, device.Tab(window, space));
        var stored = device.Authority.Current.Spaces.Single(item => item.Id == space).Tabs.Single(tab => tab.Id == rejected);
        Assert.Equal((title, address), (stored.Title, stored.Url));
    }

    [Theory]
    [InlineData("cafe\u0301", "café")]
    [InlineData("café", "cafe\u0301")]
    public void CanonicalTitleMatchingDoesNotUseNormalizedOffsetsForAddressCompletion(string typed, string host) {
        var (target, shown) = (Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(target, host + " notes", $"https://{host}.example/path"),
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")]);
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));

        var matched = device.Query(Asking(window, typed));

        Assert.Contains(matched.Groups.SelectMany(group => group.Rows), row => row.TabId == target);
        // URL completion still requires the original address prefix. A title
        // match must not slice a composed host at a decomposed query's length.
        Assert.Null(matched.Completion);
        Assert.Equal(new AddressCompletion(host, ".example", host + ".example"),
            device.Query(Asking(window, host)).Completion);
    }

    [Fact]
    public void CompletionIgnoresWwwStopsAtTheHostAndReturnOpensWhatTheFieldShows() {
        var (session, space) = PaletteSession([], ("https://www.amazon.de/gp/order-history", "Your Orders", 6, 400, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var amazon = device.Query(Asking(window, "amazon"));
        Assert.Equal(new AddressCompletion("amazon", ".de", "amazon.de"), amazon.Completion);
        var lead = amazon.Groups[0].Rows[0];
        Assert.Equal(PaletteSection.TopHit, amazon.Groups[0].Section);
        Assert.Equal(("https://www.amazon.de/", PaletteReason.Completion), (lead.Address, lead.Reason));

        Assert.Equal("p/", device.Query(Asking(window, "amazon.de/g")).Completion!.Suffix);

        // After the person deletes the completion, Return runs what they typed.
        var held = device.Query(Asking(window, "amazon") with { AllowsCompletion = false });
        Assert.Null(held.Completion);
        Assert.Equal(PaletteRowKind.Search, held.Groups[0].Rows[0].Kind);
    }

    [Fact]
    public void ATypedSchemeOpensThePlaceInThatSchemeWhereTheSpaceKnowsItInAnother() {
        var (session, space) = PaletteSession([OpenTab(Guid.NewGuid(), "Privacy error", "https://10.0.0.1/")],
            ("https://10.0.0.1/", "Privacy error", 2, 3, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var typed = device.Query(Asking(window, "http://10.0.0.1")).Groups.SelectMany(group => group.Rows).First();

        Assert.Equal((PaletteRowKind.OpenAddress, "http://10.0.0.1"), (typed.Kind, typed.Address));
    }

    [Fact]
    public void APageVisitedOnceCompletesOnlyAfterThePersonTypesIt() {
        var (session, space) = PaletteSession([], ("https://news.example.org/today", "Today", 1, 2, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);
        Assert.Null(device.Query(Asking(window, "news")).Completion);

        var history = device.Query(Asking(window, "news")).Groups.SelectMany(group => group.Rows).First(row => row.Kind == PaletteRowKind.History);
        device.Send(new RecordPaletteChoice(window, "news", history));

        Assert.Equal(".example.org", device.Query(Asking(window, "news")).Completion?.Suffix);
    }

    [Fact]
    public void APlaceShowsOnceAsItsStrongestKind() {
        var (open, shown) = (Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(open, "Field notes", "https://example.org/notes"),
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")], ("http://www.example.org/notes", "Field notes", 3, 30, 2));
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));

        var rows = device.Query(Asking(window, "field notes")).Groups.SelectMany(group => group.Rows).ToList();

        Assert.Single(rows, row => row.TabId == open);
        Assert.DoesNotContain(rows, row => row.Kind == PaletteRowKind.History);
    }

    [Fact]
    public void PicksForTheSameTextLeadThePaletteAndCanBeForgotten() {
        var (session, space) = PaletteSession([], ("https://gitlab.example.com/board", "Board", 1, 20, 10),
            ("https://github.example.com/home", "Gizmos", 1, 20, 10));
        using var device = new TestDevice(session);
        var window = device.Open(space);
        PaletteRow Board() => device.Query(Asking(window, "gi")).Groups.SelectMany(group => group.Rows)
            .First(row => row.Address == "https://gitlab.example.com/board");

        device.Send(new RecordPaletteChoice(window, "gi", Board()));
        device.Send(new RecordPaletteChoice(window, "gi", Board()));
        var learned = device.Query(Asking(window, "gi"));

        Assert.Equal(PaletteSection.TopHit, learned.Groups[0].Section);
        Assert.Equal(("https://gitlab.example.com/board", PaletteReason.Learned), (learned.Groups[0].Rows[0].Address, learned.Groups[0].Rows[0].Reason));
        Assert.Null(learned.Completion);

        device.Send(new ForgetPaletteChoices(window, Board()));
        Assert.NotEqual(PaletteReason.Learned, device.Query(Asking(window, "gi")).Groups[0].Rows[0].Reason);
    }

    [Fact]
    public void APrivateWindowRemembersNothing() {
        var (session, space) = PaletteSession([], ("https://news.example.org/today", "Today", 1, 2, 1));
        using var device = new TestDevice(session, WorkspaceKind.Named("private"));
        var window = device.Open(space);
        var history = device.Query(Asking(window, "news")).Groups.SelectMany(group => group.Rows).First(row => row.Kind == PaletteRowKind.History);

        device.Send(new RecordPaletteChoice(window, "news", history));
        device.Send(new RecordPaletteChoice(window, "news", history));

        var answer = device.Query(Asking(window, "news"));
        Assert.Null(answer.Completion);
        Assert.DoesNotContain(answer.Groups.SelectMany(group => group.Rows), row => row.Reason == PaletteReason.Learned);
    }

    [Fact]
    public void ProvidersAnswerOnlyToTheirExactNamesAndSearchOnlyTheirOwnAddress() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        device.Send(new SetSearchProviderEnabled(BuiltInSearchProvider.Reddit, IsEnabled: false));
        device.Send(new SetSearchProviderEnabled(BuiltInSearchProvider.ChatGPT, IsEnabled: true));

        Assert.Equal(("youTube", true), Offered("yt"));
        Assert.Equal(("youTube", false), Offered("www.youtube.com/"));
        Assert.Equal(("duckDuckGo", true), Offered("DG"));
        // A word that starts a provider's name offers it, but only its shortcut wins Tab over a completion.
        Assert.Equal(("youTube", false), Offered("you"));
        Assert.Equal(["chatGPT"], device.Query(Asking(window, "chat")).MatchingProviders.Select(provider => provider.Name));
        Assert.Empty(device.Query(Asking(window, "chat gpt")).MatchingProviders);
        Assert.Null(device.Query(Asking(window, "r")).OfferedSearch);

        var youTube = device.Authority.SearchCatalog.Resolving(BuiltInSearchProvider.YouTube);
        var searching = device.Query(Asking(window, "crest & browser") with { Provider = youTube });
        var row = Assert.Single(Assert.Single(searching.Groups).Rows);
        Assert.Equal(("https://www.youtube.com/results?search_query=crest%20%26%20browser", "youTube"), (row.Address, row.Provider?.Name));
        Assert.Null(searching.Completion);
        // What the provider suggests searches the provider too.
        var suggested = device.Query(Asking(window, "crest") with { Provider = youTube, Remote = ["crest browser"] });
        Assert.Equal("https://www.youtube.com/results?search_query=crest%20browser",
            Assert.Single(suggested.Groups.Single(group => group.Section == PaletteSection.SearchSuggestions).Rows).Address);

        // The notation's sign before an exact name enters it on the space, keeping what follows.
        Assert.Equal(["youTube"], device.Query(Asking(window, "$yt")).MatchingProviders.Select(provider => provider.Name).Take(1));
        var entered = device.Query(Asking(window, "$yt crest browser"));
        Assert.Equal(("youTube", "crest browser"), (entered.Entry?.Provider?.Name, entered.Entry?.Text));
        Assert.Equal("https://www.youtube.com/results?search_query=crest%20browser", entered.Groups[0].Rows[0].Address);
        Assert.Equal((PaletteScope.Tabs, ""), (device.Query(Asking(window, "@tabs ")).Entry?.Scope, device.Query(Asking(window, "@tabs ")).Entry?.Text));
        Assert.Null(device.Query(Asking(window, "$you tube")).Entry);
        Assert.Null(device.Query(Asking(window, "$100 bills")).Entry);
        Assert.Null(device.Query(Asking(window, "yt cats")).Entry);

        (string, bool)? Offered(string text) =>
            device.Query(Asking(window, text)).OfferedSearch is { } offer ? (offer.Provider.Name, offer.BeatsCompletion) : null;
    }

    [Fact]
    public void PasteAndGoOffersTheCopiedAddressOverTheAddressThePaletteOpenedWith() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;
        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice =>
                    choice.Source == PaletteSource.PasteAndGo ? choice with { IsEnabled = true } : choice)]
            }
        }));
        PaletteRow? Pasted(string text, string? pasteboard) => device.Query(Asking(window, text) with { Pasteboard = pasteboard })
            .Groups.SelectMany(group => group.Rows).SingleOrDefault(row => row.Kind == PaletteRowKind.PasteAndGo);

        Assert.Equal("https://copied.example.org", Pasted("", "copied.example.org")?.Address);
        Assert.Equal("https://copied.example.org", Pasted("https://shown.example.net/page", "copied.example.org")?.Address);
        // Words to search, or the address the field already opens, offer nothing more.
        Assert.Null(Pasted("", "garden plans"));
        Assert.Null(Pasted("https://shown.example.net/page", "https://shown.example.net/page"));
    }

    [Fact]
    public void TheBlendedLayoutRanksEveryKindInOneList() {
        var (open, shown) = (Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(open, "Garden plans", "https://garden.example.org/"),
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")], ("https://garden.example.org/seeds", "Garden seeds", 2, 40, 3));
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));
        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;

        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with { Layout = PaletteLayout.Blended, ShowsTopHit = false }
        }));
        // Without a completion to lead, the open tab heads the one list.
        var blended = device.Query(Asking(window, "garden") with { AllowsCompletion = false });

        Assert.DoesNotContain(blended.Groups, group => group.Section == PaletteSection.Tabs || group.Section == PaletteSection.History);
        var results = blended.Groups.Single(group => group.Section == PaletteSection.Results).Rows;
        Assert.Equal(open, results[0].TabId);
        Assert.Contains(results, row => row.Kind == PaletteRowKind.History);
    }

    [Fact]
    public void BeforeAnythingIsTypedTheKindsShowInThePersonsOrderSoTheFirstLeads() {
        var (older, recent, shown) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var recentTab = OpenTab(recent, "Recipes", "https://recipes.example.org/");
        recentTab["lastActivatedAt"] = (DateTimeOffset.UtcNow.AddMinutes(-5) - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds;
        var (session, space) = PaletteSession([OpenTab(older, "Garden plans", "https://garden.example.org/"), recentTab,
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")]);
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));
        PaletteAnswer Resting() =>
            device.Query(Asking(window, "") with { Commands = [new(ShortcutCommand.NewWindow, "New Window", "Everyday")] });

        // The tab the person was on before this one is the first row.
        var resting = Resting();
        Assert.Equal([PaletteSection.RecentTabs, PaletteSection.Actions], resting.Groups.Select(group => group.Section));
        Assert.Equal([recent, older], resting.Groups[0].Rows.Select(row => row.TabId));

        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;
        var actionsFirst = preferences.Palette with {
            Sources = [.. preferences.Palette.Sources.OrderBy(choice => choice.Source != PaletteSource.Actions)]
        };
        device.Send(new SetAppPreferences(device.Workspace, preferences with { Palette = actionsFirst }));
        Assert.Equal([PaletteSection.Actions, PaletteSection.RecentTabs], Resting().Groups.Select(group => group.Section));
    }

    [Fact]
    public void AScopeListsEveryRowOfItsKindBeforeAnythingIsTyped() {
        var (open, other, shown) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(open, "Garden plans", "https://garden.example.org/"),
            OpenTab(other, "Recipes", "https://recipes.example.org/"), OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")],
            ("https://news.example.org/today", "Today", 1, 2, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));

        var tabs = device.Query(Asking(window, "") with { Scope = PaletteScope.Tabs });
        Assert.Equal(new HashSet<Guid?> { open, other }, tabs.Groups.Single().Rows.Select(row => row.TabId).ToHashSet());
        Assert.Single(device.Query(Asking(window, "") with { Scope = PaletteScope.History }).Groups.Single().Rows);
    }

    [Fact]
    public void StoredPalettePreferencesNameEveryKindOnceAndKeepWhatTheyCannotRead() {
        var stored = JsonNode.Parse("""
            {"layout":"spiral","showsTopHit":false,"sources":[
              {"source":"history","isEnabled":false,"limit":12},{"source":"history","isEnabled":true},{"source":"telepathy"},
              {"source":"openTabs","isEnabled":true,"limit":0}]}
            """);

        var preferences = StoredSessionCodec.DecodePalettePreferences(stored);

        Assert.Equal((PaletteLayout.Sections, false), (preferences.Layout, preferences.ShowsTopHit));
        // A number of rows outside what a person may choose is the kind's own.
        Assert.Equal((12, PaletteSection.Tabs.Limit), (preferences.Limit(PaletteSource.History), preferences.Limit(PaletteSource.OpenTabs)));
        Assert.Equal(PaletteSource.All.Count, preferences.Sources.Count);
        Assert.Equal([PaletteSource.History, PaletteSource.OpenTabs], preferences.Sources.Take(2).Select(choice => choice.Source));
        Assert.False(preferences.Offers(PaletteSource.History));
        Assert.Equal(PaletteSource.ArchivedTabs.IsEnabledByDefault, preferences.Offers(PaletteSource.ArchivedTabs));
        Assert.Equal(preferences, StoredSessionCodec.DecodePalettePreferences(StoredSessionCodec.Encode(preferences)));
    }

    [Fact]
    public void WhatThePaletteRemembersSurvivesTheDeviceStore() {
        var started = new DateTimeOffset(2026, 10, 1, 9, 0, 0, TimeSpan.Zero);
        var memory = PaletteMemory.Starting(started)
            .Visited("https://www.example.org/a", null, started.AddDays(1))
            .Chose("ex", PaletteDestination.Address("https://example.org/a")!, "https://example.org/a", null, started.AddDays(2), learns: true);

        var read = PaletteMemoryDocument.Read(PaletteMemoryDocument.Write(memory))!;

        Assert.Equal(memory.Since, read.Since);
        Assert.Equal(memory.Places, read.Places);
        Assert.Equal(memory.Choices, read.Choices);
        Assert.Null(PaletteMemoryDocument.Read("{\"places\":[]}"));
    }

    [Fact]
    public void ARememberedEntryThatDoesNotReadIsLeftOutAndTheRestKept() {
        const string since = "2026-10-01T09:00:00.0000000+00:00";
        const string used = "2026-10-02T09:00:00.0000000+00:00";
        var read = PaletteMemoryDocument.Read($$"""
            {"since":"{{since}}","places":[
              {"place":"a","decayDay":3,"typedAt":"{{used}}","typedUses":2},
              {"place":"b","decayDay":4,"typedUses":-3},
              {"place":"a","decayDay":5},
              {"decayDay":6},{"place":"c"},{"place":"d","decayDay":"x"},7],
             "choices":[
              {"text":"ex","kind":"address","value":"https://example.org/","uses":2,"usedAt":"{{used}}"},
              {"text":"ex","kind":"unknown","value":"https://example.org/","uses":2,"usedAt":"{{used}}"},
              {"text":"ex","kind":"address","value":"https://example.org/","uses":2},
              {"kind":"address","value":"https://example.org/","uses":2,"usedAt":"{{used}}"},
              "choice"]}
            """)!;

        Assert.Equal(DateTimeOffset.Parse(since, CultureInfo.InvariantCulture), read.Since);
        Assert.Equal(["a", "b"], read.Places.Keys.Order(StringComparer.Ordinal));
        Assert.Equal(new PlaceUse(5, null), read.Places["a"]);
        Assert.Equal(new PlaceUse(4, null, TypedUses: 0), read.Places["b"]);
        var choice = Assert.Single(read.Choices);
        Assert.Equal(("ex", PaletteDestinationKind.Address, 2.0), (choice.Text, choice.Destination.Kind, choice.Uses));
        Assert.Null(PaletteMemoryDocument.Read(null));
        Assert.Null(PaletteMemoryDocument.Read("{"));
        Assert.Null(PaletteMemoryDocument.Read("[]"));
        Assert.Null(PaletteMemoryDocument.Read($$"""{"since":"{{since}}","places":[[[[[[[[1]]]]]]]]}"""));
        Assert.Empty(PaletteMemoryDocument.Read($$"""{"since":"{{since}}","places":{},"choices":3}""")!.Places);
    }

    [Fact]
    public void ATypedVisitCountsTwiceALinkAndUseHalvesEveryThirtyDays() {
        var day = new DateTimeOffset(2026, 10, 1, 9, 0, 0, TimeSpan.Zero);
        const string page = "https://example.org/a";
        var linked = PaletteMemory.Starting(day).Visited(page, null, day);
        var typed = PaletteMemory.Starting(day).Chose("ex", PaletteDestination.Address(page)!, page, null, day, learns: false)
            .Visited(page, null, day);

        Assert.Equal(1, linked.Frecency(page, null, day), 6);
        Assert.Equal(2, typed.Frecency(page, null, day), 6);
        Assert.Equal(0.5, linked.Frecency(page, null, day.AddDays(30)), 6);
        Assert.True(typed.WasTyped("www.example.org", day.AddDays(89)));
        Assert.False(typed.WasTyped("example.org", day.AddDays(91)));
    }

    [Theory]
    [InlineData("2+2*3", "8")]
    [InlineData("(1.5 + 2.5) ^ 2 / 4", "4")]
    [InlineData("10 % 4 − 1", "1")]
    [InlineData("-2^2", "-4")]
    [InlineData("(-2)^2", "4")]
    [InlineData("2^-2", "0.25")]
    [InlineData("2^3^2", "512")]
    [InlineData("-2^-2", "-0.25")]
    [InlineData("1e3+2", "1002")]
    [InlineData("2.5E-3 * 400", "1")]
    [InlineData("3e+2 / 2", "150")]
    [InlineData("1e3", null)]
    [InlineData("1e+ + 2", null)]
    [InlineData("1e2.5 + 2", null)]
    [InlineData("1e309 ^ 0", null)]
    [InlineData("(0/0)^0", null)]
    [InlineData("1/(1/0)", null)]
    [InlineData("((-1)^0.5)^0", null)]
    [InlineData("(1e308*1e308)^0", null)]
    [InlineData("1,5+2", null)]
    [InlineData("42", null)]
    [InlineData("2/0", null)]
    [InlineData("2 apples", null)]
    [InlineData("20% of 80", "16")]
    [InlineData("52% of 900", "468")]
    [InlineData("20% off 80", "64")]
    [InlineData("12.5% off 19.99", "17.49125")]
    [InlineData("-20% of -80", "16")]
    [InlineData("−20 % OFF 80", "96")]
    [InlineData("20% off -80", "-64")]
    [InlineData("150% off 80", "-40")]
    [InlineData("100% off 80", "0")]
    [InlineData("0% of 80", "0")]
    [InlineData("+2e1% of +8e1", "16")]
    [InlineData("100% of 1e308", "1E+308")]
    [InlineData("20% of 80+5", null)]
    [InlineData("(10+10)% of 80", null)]
    [InlineData("20% of (40+40)", null)]
    [InlineData("20%% of 80", null)]
    [InlineData("20%of 80", null)]
    [InlineData("20% of80", null)]
    [InlineData("20% of 1e+", null)]
    [InlineData("1e308% of 1e308", null)]
    [InlineData("1e308% off 1e308", null)]
    [InlineData("1e309% of 0", null)]
    [InlineData("20% of (0/0)^0", null)]
    [InlineData("80 plus 20%", null)]
    [InlineData("20%", null)]
    [InlineData("200-10%", null)]
    [InlineData("80+20%3", "82")]
    public void TheCalculatorAnswersArithmeticWithAnOperatorOnly(string typed, string? answer) =>
        Assert.Equal(answer, Calculation.Of(typed)?.Answer);

    [Fact]
    public void ACommandMatchesTextItHoldsOrItsInitialsButNeverLettersScatteredThroughIt() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        PaletteCommand[] commands = [new(ShortcutCommand.ReloadPage, "Reload Page", "Everyday Use"),
            new(ShortcutCommand.ToggleReaderMode, "Show or Hide Reader", "Page"),
            new(ShortcutCommand.ToggleSidebar, "Show or Hide Sidebar", "View & Tools")];
        string[] Matching(string text) => [.. device.Query(Asking(window, text) with { Commands = commands }).Groups
            .SelectMany(group => group.Rows).Where(row => row.Kind == PaletteRowKind.Command).Select(row => row.Title)];

        Assert.Empty(Matching("ode"));
        Assert.Equal(["Reload Page"], Matching("relo"));
        Assert.Equal(["Show or Hide Sidebar"], Matching("sohs"));
        Assert.Contains("Reload Page", Matching("page"));
    }

    /// A saved session with only `tabs` and `history` in its one Space, each
    /// history entry first and last visited that many days ago.
    private static (JsonNode Session, Guid Space) PaletteSession(JsonNode[] tabs,
        params (string Url, string Title, int Visits, double FirstDaysAgo, double LastDaysAgo)[] history) {
        var (document, space, _) = SavedSession();
        var saved = document["session"]!["spaces"]![0]!;
        saved["tabs"] = new JsonArray(tabs);
        saved["folders"] = new JsonArray();
        saved.AsObject().Remove("selectedTabID");
        double now = (DateTimeOffset.UtcNow - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds;
        saved["history"] = new JsonArray([.. history.OrderBy(entry => entry.LastDaysAgo).Select(entry => (JsonNode)new JsonObject {
            ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(),
            ["url"] = entry.Url,
            ["title"] = entry.Title,
            ["firstVisitedAt"] = now - entry.FirstDaysAgo * 86_400,
            ["lastVisitedAt"] = now - entry.LastDaysAgo * 86_400,
            ["visitCount"] = entry.Visits
        })]);
        return (document["session"]!, space);
    }

    /// An open tab showing `url`, last used a week ago.
    private static JsonObject OpenTab(Guid id, string title, string url) => new() {
        ["id"] = SwiftId(id),
        ["title"] = title,
        ["url"] = url,
        ["placement"] = "current",
        ["symbol"] = "globe",
        ["lastActivatedAt"] = (DateTimeOffset.UtcNow.AddDays(-7) - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds
    };
}
