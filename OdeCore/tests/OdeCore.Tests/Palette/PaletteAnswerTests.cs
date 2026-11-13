using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// How the palette uses the written answers: a question leads with its
/// answer, whose row carries the card and what "Do it" runs, while an address,
/// a site's name, or a question about something else that shares a word or
/// two with an answer searches; and "help" or "ode" and Tab, or "?" and a
/// space, narrow the palette to Ode Help, which lists only answers.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void AQuestionLeadsThePaletteWithItsAnswer() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var asked = device.Query(Asking(window, "how do I split view"));
        var lead = asked.Groups[0].Rows[0];
        Assert.Equal((PaletteSection.TopHit, PaletteRowKind.Answer, "split-view-create"), (asked.Groups[0].Section, lead.Kind, lead.Answer?.Id));
        Assert.Equal(PaletteReason.Answers, lead.Reason);
        Assert.Contains(asked.Groups.SelectMany(group => group.Rows), row => row.Kind == PaletteRowKind.Search);

        var settings = device.Query(Asking(window, "settings")).Groups[0].Rows[0];
        Assert.Equal(("open-settings", "settings"), (settings.Answer?.Id, settings.Answer?.Action?.ApplicationAction));
        Assert.Equal(ShortcutCommand.ReopenClosedTab, device.Query(Asking(window, "undo close tab")).Groups[0].Rows[0].Answer?.Action?.Command);

        foreach (var text in new[] { "github", "taylor swift", "example.org" })
            Assert.DoesNotContain(device.Query(Asking(window, text)).Groups.SelectMany(group => group.Rows), row => row.Kind == PaletteRowKind.Answer);
    }

    [Theory]
    [InlineData("explain the difference between tcp and udp")]
    [InlineData("what time is it in tokyo right now")]
    [InlineData("how long should I boil an egg")]
    [InlineData("what's the population of switzerland")]
    [InlineData("what are the side effects of ibuprofen")]
    [InlineData("python sort dict by value")]
    public void AQuestionAboutSomethingElseSearchesThoughAnAnswerSharesAWordWithIt(string text) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var asked = device.Query(Asking(window, text));

        Assert.DoesNotContain(asked.Groups, group => group.Section == PaletteSection.TopHit);
        Assert.Equal(PaletteRowKind.Search, asked.Groups[0].Rows[0].Kind);
    }

    [Fact]
    public void HelpOrOdeAndTabOrAQuestionMarkNarrowThePaletteToAnswers() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);

        Assert.Equal(PaletteScope.Help, device.Query(Asking(window, "help")).OfferedScope);
        Assert.Equal(PaletteScope.Help, device.Query(Asking(window, "Ode")).OfferedScope);
        Assert.Null(device.Query(Asking(window, "helpful")).OfferedScope);
        var entered = device.Query(Asking(window, "? pin a tab"));
        Assert.Equal((PaletteScope.Help, "pin a tab"), (entered.Entry?.Scope, entered.Entry?.Text));

        var scoped = device.Query(Asking(window, "split view") with { Scope = PaletteScope.Help });
        var rows = Assert.Single(scoped.Groups).Rows;
        Assert.All(rows, row => Assert.Equal(PaletteRowKind.Answer, row.Kind));
        Assert.Equal("split-view-create", rows[0].Answer?.Id);
        Assert.InRange(rows.Count, 2, PaletteSection.Answer.ScopedLimit);
        var resting = device.Query(Asking(window, "") with { Scope = PaletteScope.Help });
        Assert.Equal("open-command-bar", Assert.Single(resting.Groups).Rows[0].Answer?.Id);
    }
}
