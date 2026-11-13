using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// What leads the palette over a search: a word that spells a settings page
/// leads with the page, while a command leads only once the text spells most
/// of its title or names it in words, and then over a written answer about
/// it; and a site search entered with nothing typed still opens the site.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASettingsPageOutranksASearchWhileACommandNeedsMostOfItsTitle() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        PaletteSettingsPage[] pages = [new("agents", "Agents", "Coding agents and scripts"), new("engines", "Engines", "Default engine")];
        // Titles no written answer names, so only the title rule can lead.
        PaletteCommand[] commands = [new(ShortcutCommand.ReloadPage, "Fold Paper Crane", "Everyday Use"),
            new(ShortcutCommand.ZoomIn, "Zoom In", "Page")];
        PaletteRow First(string text) => device.Query(Asking(window, text) with { SettingsPages = pages, Commands = commands }).Groups[0].Rows[0];

        Assert.Equal((PaletteRowKind.SettingsPage, "agents"), (First("agents").Kind, First("agents").SettingsPage));
        Assert.Equal((PaletteRowKind.SettingsPage, "engines"), (First("engi").Kind, First("engi").SettingsPage));
        Assert.Equal(ShortcutCommand.ReloadPage, First("fold paper").Command);
        Assert.Equal(PaletteRowKind.Search, First("fold").Kind);
        Assert.Equal(PaletteRowKind.Search, First("zoom").Kind);
        Assert.Equal(PaletteRowKind.Search, First("ag").Kind);
    }

    /// Each command a person might type, with the kind of row Return runs and
    /// the command it runs, directly or through an answer's "Do it": a command
    /// whose title the text names leads; text that names no title leaves the
    /// answer about it, or the search when no command does what it asks.
    [Theory]
    [InlineData("new private window", "command", "newPrivateWindow")]
    [InlineData("pin tab", "command", "toggleSelectedTabPinned")]
    [InlineData("reopen closed tab", "command", "reopenClosedTab")]
    [InlineData("close this window", "command", "closeWindow")]
    [InlineData("duplicate tab", "command", "duplicateTab")]
    [InlineData("zoom in", "command", "zoomIn")]
    [InlineData("copy url", "answer", "copyPageLink")]
    [InlineData("split view with github", "answer", "splitWithNextTab")]
    [InlineData("go back", "answer", "back")]
    [InlineData("toggle sidebar", "answer", "toggleSidebar")]
    [InlineData("clear browsing history", "answer", "showHistory")]
    [InlineData("mute this tab", "answer", null)]
    [InlineData("bookmark this page", "answer", null)]
    [InlineData("close all other tabs", "search", null)]
    [InlineData("open new tab", "search", null)]
    [InlineData("unmute all tabs", "search", null)]
    public void ACommandTheTextNamesLeadsOverAWrittenAnswerAboutIt(string text, string kind, string? command) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        PaletteCommand[] commands = [.. ShortcutCommand.All.Where(offered => offered.OffersInPalette)
            .Select(offered => new PaletteCommand(offered, offered.Title, offered.Section.Title))];

        var first = device.Query(Asking(window, text) with { Commands = commands }).Groups[0].Rows[0];

        Assert.Equal((kind, command), (first.Kind.Name, (first.Command ?? first.Answer?.Action?.Command)?.Name));
    }

    [Fact]
    public void ASiteSearchWithNothingTypedOpensTheSite() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        var spotify = device.Authority.SearchCatalog.Resolving(BuiltInSearchProvider.Spotify);

        var row = Assert.Single(Assert.Single(device.Query(Asking(window, "") with { Provider = spotify }).Groups).Rows);

        Assert.Equal((PaletteRowKind.OpenAddress, "https://open.spotify.com/", "Open Spotify"), (row.Kind, row.Address, row.Title));
    }
}
