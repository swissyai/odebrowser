using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// Where Shift-Return takes a search: to its first result through
/// DuckDuckGo's backslash, with the person's DuckDuckGo options, or through
/// Kagi's own when Kagi is the Space's engine. The search row and every
/// suggestion carry it; an address, an assistant and a website have none;
/// a private window has one too, since the person asks for it; and a Quick
/// Window resolves typed text to the same place.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASearchRowOpensItsFirstResultThroughDuckDuckGo() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        device.Send(new SetSpaceSearch(device.Workspace, space, device.Authority.SearchCatalog.Resolving(BuiltInSearchProvider.Google),
            SuggestionsEnabled: null));

        var search = SearchRow(device.Query(Asking(window, "albert einstein")));
        Assert.StartsWith("https://www.google.com/search?q=albert%20einstein", search.Address);
        Assert.StartsWith("https://duckduckgo.com/?q=%5Calbert%20einstein", search.TopResult);
        Assert.Null(SearchRow(device.Query(Asking(window, "github.com")), PaletteRowKind.OpenAddress).TopResult);

        var suggested = device.Query(Asking(window, "albert einstein") with { Remote = ["albert einstein quotes"] })
            .Groups.Single(group => group.Section == PaletteSection.SearchSuggestions).Rows.Single();
        Assert.StartsWith("https://duckduckgo.com/?q=%5Calbert%20einstein%20quotes", suggested.TopResult);
    }

    [Fact]
    public void TheFirstResultKeepsDuckDuckGoOptionsAndUsesKagiForKagiSpaces() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        var catalog = device.Authority.SearchCatalog;

        device.Send(new SetSearchOption(BuiltInSearchProvider.DuckDuckGo, SearchProviderOption.DuckDuckGoRegion, "de-de"));
        Assert.Contains("kl=de-de", SearchRow(device.Query(Asking(window, "lisbon"))).TopResult, StringComparison.Ordinal);

        device.Send(new SetSpaceSearch(device.Workspace, space, catalog.Resolving(BuiltInSearchProvider.Kagi), SuggestionsEnabled: null));
        var kagi = SearchRow(device.Query(Asking(window, "lisbon")));
        Assert.Equal(("https://kagi.com/search?q=lisbon", "https://kagi.com/search?q=%5Clisbon"), (kagi.Address, kagi.TopResult));
    }

    [Fact]
    public void AnAssistantOrAWebsiteHasNoFirstResult() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        var catalog = device.Authority.SearchCatalog;

        foreach (var provider in new[] { BuiltInSearchProvider.YouTube, BuiltInSearchProvider.ChatGPT })
            Assert.Null(SearchRow(device.Query(Asking(window, "cats") with { Provider = catalog.Resolving(provider) })).TopResult);
        var bing = SearchRow(device.Query(Asking(window, "cats") with { Provider = catalog.Resolving(BuiltInSearchProvider.Bing) }));
        Assert.StartsWith("https://duckduckgo.com/?q=%5Ccats", bing.TopResult);
    }

    [Fact]
    public void APrivateWindowStillOpensTheFirstResultWhenAsked() {
        var (document, space, _) = SavedSession();
        using var device = new TestDevice(document["session"]!, WorkspaceKind.Named("private"));
        var window = device.Open(space);

        var answer = device.Query(Asking(window, "albert einstein"));
        Assert.Null(answer.SuggestionAddress);
        Assert.StartsWith("https://duckduckgo.com/?q=%5Calbert%20einstein", SearchRow(answer).TopResult);
    }

    [Fact]
    public void AQuickWindowResolvesTypedTextToTheSameFirstResult() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);

        var searched = device.Query(new ResolveAddress(device.Workspace, space, "figma login"));
        Assert.StartsWith("https://duckduckgo.com/?q=%5Cfigma%20login", searched.TopResult);
        Assert.Null(device.Query(new ResolveAddress(device.Workspace, space, "figma.com")).TopResult);
    }

    /// The first row of `kind` in `answer`.
    private static PaletteRow SearchRow(PaletteAnswer answer, PaletteRowKind? kind = null) =>
        answer.Groups.SelectMany(group => group.Rows).First(row => row.Kind == (kind ?? PaletteRowKind.Search));
}
