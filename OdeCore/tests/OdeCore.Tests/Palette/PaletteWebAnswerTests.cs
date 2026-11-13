using System.Text.Json.Nodes;

using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// The encyclopedia card a person may turn on in Settings > Search: off by
/// default; once on, the palette names a Wikipedia lookup for a topic, never
/// in a private window, for an address, a secret or a local match; a summary
/// shows only when its title is exactly the topic, as a standard article,
/// with a picture only when Commons holds it freely licensed with its author,
/// and with Wikipedia's credit and licence.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void WebAnswersAreOffUntilThePersonTurnsThemOn() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        Assert.Null(device.Query(Asking(device.Open(space), "albert einstein")).WebLookup);
    }

    [Fact]
    public void ATopicIsLookedUpOnTheWikipediaThePersonSearches() {
        var (device, window) = WebAnswering();
        using (device) {
            var lookup = device.Query(Asking(window, "who is Albert Einstein?")).WebLookup!;
            Assert.Equal("Albert Einstein", lookup.Topic);
            Assert.Equal("https://en.wikipedia.org/w/rest.php/v1/search/title?q=Albert%20Einstein&limit=1", lookup.SearchAddress);
            Assert.Equal("https://en.wikipedia.org/api/rest_v1/page/summary/%s", lookup.SummaryTemplate);
            Assert.StartsWith("https://commons.wikimedia.org/w/api.php?", lookup.ImageInfoTemplate);

            device.Send(new SetSearchOption(BuiltInSearchProvider.Wikipedia, SearchProviderOption.WikipediaLanguage, "de"));
            Assert.StartsWith("https://de.wikipedia.org/", device.Query(Asking(window, "lisbon")).WebLookup!.SearchAddress);

            foreach (string text in new[] { "github.com", "youtube", "ghp_0123456789abcdefABCDEF0123456789", "jane.doe@example.com", "5 km in miles",
                "time in tokyo", "ab", "24 * 7" })
                Assert.Null(device.Query(Asking(window, text)).WebLookup);
        }
    }

    [Theory]
    [InlineData("persistent", true)]
    [InlineData("private", false)]
    public void APrivateWindowLooksNothingUp(string kind, bool looksUp) {
        var (document, space, _) = SavedSession();
        var session = document["session"]!;
        session["appPreferences"] = new JsonObject {
            ["palette"] = new JsonObject { ["sources"] = new JsonArray(new JsonObject { ["source"] = "webAnswers", ["isEnabled"] = true }) }
        };
        using var device = new TestDevice(session, WorkspaceKind.Named(kind));
        Assert.Equal(looksUp, device.Query(Asking(device.Open(space), "albert einstein")).WebLookup is not null);
    }

    [Fact]
    public void ASummaryShowsOnlyForTheExactTopicWithAFreePictureAndItsCredit() {
        var (device, window) = WebAnswering();
        using (device) {
            const string portrait = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Einstein_1921.jpg/320px-Einstein_1921.jpg";
            var summary = new PaletteWebSummary("Albert Einstein", "standard", "German-born theoretical physicist (1879–1955)",
                "Albert Einstein was a German-born theoretical physicist who is best known for developing the theory of relativity. "
                    + "Einstein also made important contributions to quantum mechanics. His mass–energy equivalence formula is famous.",
                "https://en.wikipedia.org/wiki/Albert_Einstein", portrait, "Ferdinand Schmutzer", "Public domain");
            PaletteAnswer Asked(string text, PaletteWebSummary fetched) => device.Query(Asking(window, text) with { WebSummary = fetched });

            var answer = Asked("albert einstein", summary);
            Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
            Assert.Null(answer.WebLookup);
            var card = CardOf(answer);
            Assert.Equal((PaletteCardKind.Encyclopedia, "Albert Einstein", "https://en.wikipedia.org/wiki/Albert_Einstein"),
                (card.Kind, card.Title, card.Address));
            Assert.Equal(("Wikipedia", "CC BY-SA 4.0"), (card.Credit, card.License));
            Assert.True(card.Body!.Length <= 240 && card.Body.EndsWith('.'), card.Body);
            Assert.Equal(portrait, card.Image?.Address);
            Assert.Equal("Photo: Ferdinand Schmutzer, Public domain", card.Image?.Credit);
            Assert.Equal("https://commons.wikimedia.org/wiki/File:Einstein_1921.jpg", card.Image?.CreditAddress);

            // A picture outside Commons, or without its licence and author, stays out.
            Assert.Null(CardOf(Asked("albert einstein", summary with {
                Thumbnail = "https://upload.wikimedia.org/wikipedia/en/thumb/a/ab/Poster.jpg/320px-Poster.jpg"
            })).Image);
            Assert.Null(CardOf(Asked("albert einstein", summary with { ImageArtist = null })).Image);
            Assert.Null(CardOf(Asked("albert einstein", summary with { ImageLicense = "Fair use" })).Image);

            // Another title, a list or a disambiguation page shows nothing.
            Assert.DoesNotContain(Asked("time in togo now", summary with { Title = "Time in Togo" }).Groups,
                group => group.Section == PaletteSection.Card);
            Assert.DoesNotContain(Asked("einstein", summary).Groups, group => group.Section == PaletteSection.Card);
            Assert.DoesNotContain(Asked("albert einstein", summary with { Type = "disambiguation" }).Groups,
                group => group.Section == PaletteSection.Card);
        }
    }

    /// A device with web answers on and a window over its only Space.
    private static (TestDevice Device, Guid Window) WebAnswering() {
        var (session, space) = PaletteSession([]);
        var device = new TestDevice(session);
        TurnOnWebAnswers(device);
        return (device, device.Open(space));
    }

    private static void TurnOnWebAnswers(TestDevice device) {
        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;
        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice =>
                    choice.Source == PaletteSource.WebAnswers ? choice with { IsEnabled = true } : choice)]
            }
        }));
    }
}
