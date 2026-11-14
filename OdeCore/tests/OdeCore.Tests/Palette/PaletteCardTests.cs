using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// The one short answer the palette shows below the search, worked out on
/// the device: unit conversions, the time somewhere, and a definition the
/// platform looked up in the Mac's dictionary. The search still leads, the
/// card copies or looks up, and each kind turns off on its own.
public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("27 * 14", "378")]
    [InlineData("  20 % Of 80  ", "16")]
    [InlineData("20% off 80", "64")]
    public void ArithmeticKeepsSearchAsReturnAndOffersOneLocalCopyAction(string typed, string value) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        device.Send(new SetSearchSuggestions(true));
        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;
        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice =>
                    choice.Source == PaletteSource.WebAnswers ? choice with { IsEnabled = true } : choice)]
            }
        }));

        var answer = device.Query(Asking(window, typed));

        Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
        var card = CardOf(answer);
        Assert.Equal((value, $"{typed.Trim()} =", value), (card.Title, card.Subtitle, card.Value));
        Assert.True(card.Kind.CopiesValue);
        Assert.Null(answer.SuggestionAddress);
        Assert.Null(answer.WebLookup);
        Assert.Null(answer.DefinitionTerm);
        Assert.Single(answer.Groups.SelectMany(group => group.Rows), row => row.Card is not null);
        Assert.DoesNotContain(answer.Groups.SelectMany(group => group.Rows), row => row.Kind == PaletteRowKind.Calculation);

        preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;
        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice =>
                    choice.Source == PaletteSource.Calculator ? choice with { IsEnabled = false } : choice)]
            }
        }));
        Assert.DoesNotContain(device.Query(Asking(window, typed)).Groups, group => group.Section == PaletteSection.Card);
    }

    [Theory]
    [InlineData("5 km in miles", "3.107 miles", "5 kilometers =", "3.107")]
    [InlineData("72 f to c", "22.22 degrees Celsius", "72 degrees Fahrenheit =", "22.22")]
    [InlineData("convert 2 cups to ml", "473.2 milliliters", "2 US cups =", "473.2")]
    [InlineData("how many ounces in a pound", "16 ounces", "1 pound =", "16")]
    [InlineData("how many ounces in pound", "16 ounces", "1 pound =", "16")]
    [InlineData("how many ounces in 2pounds", "32 ounces", "2 pounds =", "32")]
    [InlineData("16 oz in pounds", "1 pound", "16 ounces =", "1")]
    [InlineData("ounces to pounds", "0.0625 pounds", "1 ounce =", "0.0625")]
    [InlineData("grams to kilograms", "0.001 kilograms", "1 gram =", "0.001")]
    [InlineData("tsp to ml", "4.929 milliliters", "1 US teaspoon =", "4.929")]
    [InlineData("how many oz in a pound?", "16 ounces", "1 pound =", "16")]
    [InlineData("how many fluid ounces in a US cup", "8 US fluid ounces", "1 US cup =", "8")]
    [InlineData("how many fluid ounces in a cup", "8 US fluid ounces", "1 US cup =", "8")]
    [InlineData("10 inches to cm", "25.4 centimeters", "10 inches =", "25.4")]
    [InlineData("60 mph in km/h", "96.56 kilometers per hour", "60 miles per hour =", "96.56")]
    [InlineData("1.5 gb to mb", "1500 megabytes", "1.5 gigabytes =", "1500")]
    [InlineData("1,000 km in miles", "621.4 miles", "1000 kilometers =", "621.4")]
    public void AConversionShowsAsACardBelowTheSearch(string text, string title, string subtitle, string value) {
        var (device, window) = SuggestingPalette([]);
        using var ownedDevice = device;
        EnablePrivateAnswers(device);
        var answer = device.Query(Asking(window, text));

        Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
        var card = CardOf(answer);
        Assert.Equal((PaletteCardKind.Conversion, title, subtitle, value), (card.Kind, card.Title, card.Subtitle, card.Value));
        Assert.Null(answer.GenerativeLookup);
        Assert.Null(answer.SuggestionAddress);
        Assert.Null(answer.WebLookup);
    }

    /// Digits grouped in threes by a comma or a space are one amount; a comma
    /// before any other run of digits is a decimal comma, and a point is only
    /// ever the decimal point.
    [Theory]
    [InlineData("1,000 km in miles", 1000)]
    [InlineData("1 000 km in miles", 1000)]
    [InlineData("12,345 km in miles", 12345)]
    [InlineData("1,000,000 m in km", 1_000_000)]
    [InlineData("1,000.5 km in miles", 1000.5)]
    [InlineData("1 000.5 km in miles", 1000.5)]
    [InlineData("0,5 km in m", 0.5)]
    [InlineData("0,500 km in m", 0.5)]
    [InlineData("1,5 km in m", 1.5)]
    [InlineData("3,14159 m in cm", 3.14159)]
    [InlineData("1.000 km in m", 1)]
    [InlineData("-40,5 c to f", -40.5)]
    [InlineData("how many miles in 1,000 km", 1000)]
    [InlineData("how many miles are in 1 000 km?", 1000)]
    public void AnAmountReadsThousandsGroupsAndADecimalComma(string typed, double amount) {
        var conversion = UnitConversion.Of(typed);
        Assert.NotNull(conversion);
        Assert.Equal(amount, conversion.Amount);
    }

    [Theory]
    [InlineData("1,00,0 km in m")]
    [InlineData("1 00 km in m")]
    [InlineData("1,000,5 km in m")]
    [InlineData("1.000,5 km in m")]
    public void AnAmountWhoseGroupsDoNotReadAsksNoConversion(string typed) => Assert.Null(UnitConversion.Of(typed));

    [Theory]
    [InlineData("ounces to poundcake")]
    [InlineData("grams to teaspoons recipe")]
    [InlineData("5 grams of chicken to tsp")]
    [InlineData("5 grams chicken to tsp")]
    [InlineData("grams to tsp of chicken")]
    [InlineData("grams to grams")]
    [InlineData("grams to")]
    [InlineData("how many ounces in")]
    [InlineData("how many ounces in po")]
    [InlineData("how many ounces in pound cake")]
    [InlineData("how many ounces in 1,00,0 pounds")]
    [InlineData("1,00,0 grams to tsp")]
    [InlineData("grams to km")]
    [InlineData("c to f")]
    [InlineData("how many people in pound")]
    [InlineData("https://example.org/grams to tsp")]
    [InlineData("1 in 3 people")]
    [InlineData("5 km")]
    [InlineData("iphone 15 to 16")]
    [InlineData("5 km in kg")]
    [InlineData("screen time")]
    [InlineData("time machine")]
    [InlineData("time in narnia")]
    [InlineData("20% off 80 shoes")]
    [InlineData("what is 20% of 80")]
    [InlineData("20% offer 80")]
    [InlineData("https://example.org/?q=20%25+of+80")]
    [InlineData("example.com 20% of 80")]
    public void TextThatAsksNoConversionOrTimeHasNoCard(string text) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        Assert.DoesNotContain(device.Query(Asking(device.Open(space), text)).Groups, group => group.Section == PaletteSection.Card);
    }

    [Theory]
    [InlineData("grams to tsp")]
    [InlineData("5 grams to tsp")]
    [InlineData("ask ode 5 grams to tsp")]
    [InlineData("5 tsp to grams")]
    [InlineData("how many oz in a cup")]
    [InlineData("how many oz in a US cup")]
    public void MassAndVolumeAskForDensityWithoutInventingACopyableAnswerOrRequestingServices(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var answer = device.Query(Asking(window, text));
            var card = CardOf(answer);

            Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
            Assert.Equal(PaletteCardKind.Clarification, card.Kind);
            Assert.False(card.Kind.CopiesValue);
            Assert.False(card.Kind.LooksUpTerm);
            Assert.Null(card.Value);
            Assert.Null(card.Address);
            Assert.Null(card.Term);
            Assert.Null(answer.GenerativeLookup);
            Assert.Null(answer.SuggestionAddress);
            Assert.Null(answer.WebLookup);
            Assert.Null(answer.DefinitionTerm);
            Assert.Null(UnitConversion.Of(text));

            var preferences = device.Authority.Current.AppPreferences!;
            device.Send(new SetAppPreferences(device.Workspace, preferences with {
                Palette = preferences.Palette with {
                    Sources = [.. preferences.Palette.Sources.Select(choice => choice.Source == PaletteSource.Conversions
                        ? choice with { IsEnabled = false } : choice)]
                }
            }));
            Assert.DoesNotContain(device.Query(Asking(window, text)).Groups,
                group => group.Rows.Any(row => row.Card?.Kind == PaletteCardKind.Clarification));
        }
    }

    [Theory]
    [InlineData("time in tokyo", "Asia/Tokyo", "Tokyo")]
    [InlineData("what time is it in london?", "Europe/London", "London")]
    [InlineData("sydney time", "Australia/Sydney", "Sydney")]
    [InlineData("current time in san francisco", "America/Los_Angeles", "Los Angeles")]
    public void TheTimeSomewhereShowsNowThereAndHowFarAheadItIs(string text, string zone, string place) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var card = CardOf(device.Query(Asking(device.Open(space), text)));

        Assert.Equal((PaletteCardKind.Time, zone, place, (string?)null), (card.Kind, card.Clock!.Zone, card.Clock.Place, card.Clock.FromZone));
        Assert.InRange(card.Clock.Instant, DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddMinutes(1));
        var there = TimeZoneInfo.FindSystemTimeZoneById(zone).GetUtcOffset(card.Clock.Instant);
        int ahead = (int)(there - TimeZoneInfo.Local.GetUtcOffset(card.Clock.Instant)).TotalMinutes;
        Assert.Equal(ahead == 0 ? "Same time" : ahead > 0 ? "ahead" : "behind", card.Subtitle.Split(' ')[^1] is "time" ? "Same time"
            : card.Subtitle.Split(' ')[^1]);
    }

    [Fact]
    public void ATimeOfDayInOnePlaceShowsAsItFallsInAnother() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var card = CardOf(device.Query(Asking(device.Open(space), "3pm new york time in tokyo")));

        Assert.Equal(("America/New_York", "New York", "Asia/Tokyo", "Tokyo"),
            (card.Clock!.FromZone, card.Clock.FromPlace, card.Clock.Zone, card.Clock.Place));
        var newYork = TimeZoneInfo.FindSystemTimeZoneById("America/New_York");
        Assert.Equal(15, TimeZoneInfo.ConvertTime(card.Clock.Instant, newYork).Hour);
        var tokyo = TimeZoneInfo.FindSystemTimeZoneById("Asia/Tokyo");
        int hours = (int)(tokyo.GetUtcOffset(card.Clock.Instant) - newYork.GetUtcOffset(card.Clock.Instant)).TotalHours;
        Assert.Equal($"{hours} hours ahead", card.Subtitle);
        Assert.Equal("9:30", CardOf(device.Query(Asking(device.Open(space), "9:30 pst to est"))).Clock!.Instant
            .ToOffset(TimeZoneInfo.FindSystemTimeZoneById("America/Los_Angeles").GetUtcOffset(DateTimeOffset.UtcNow)).ToString("H:mm"));
    }

    [Fact]
    public void AWordIsLookedUpInTheDictionaryAndItsEntryShowsAsACard() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);

        Assert.Equal("ephemeral", device.Query(Asking(window, "define ephemeral")).DefinitionTerm);
        Assert.Equal("ephemeral", device.Query(Asking(window, "what does ephemeral mean")).DefinitionTerm);
        Assert.Equal("serendipity", device.Query(Asking(window, "serendipity")).DefinitionTerm);
        foreach (string text in new[] { "github.com", "youtube", "albert einstein", "P@ssw0rd123", "24 * 7" })
            Assert.Null(device.Query(Asking(window, text)).DefinitionTerm);

        const string entry = "e·phem·er·al | əˈfem(ə)rəl | adjective lasting for a very short time: fashions are ephemeral.";
        var defined = device.Query(Asking(window, "define ephemeral") with { Definition = new("ephemeral", entry) });
        var card = CardOf(defined);
        Assert.Equal((PaletteCardKind.Definition, "e·phem·er·al", "əˈfem(ə)rəl", "ephemeral"), (card.Kind, card.Title, card.Subtitle, card.Term));
        Assert.StartsWith("adjective lasting", card.Body);
        Assert.Null(defined.DefinitionTerm);
        Assert.Equal(PaletteRowKind.Search, defined.Groups[0].Rows[0].Kind);
        // The Mac writes the plain word before its divided spelling.
        Assert.Equal("e·phem·er·al", CardOf(device.Query(Asking(window, "define ephemeral") with {
            Definition = new("ephemeral", "ephemeral " + entry)
        })).Title);

        // A Mac without its dictionary yet says so only when asked outright.
        Assert.Contains("downloading", CardOf(device.Query(Asking(window, "define ephemeral") with { Definition = new("ephemeral", null) })).Body);
        Assert.DoesNotContain(device.Query(Asking(window, "ephemeral") with { Definition = new("ephemeral", null) }).Groups,
            group => group.Section == PaletteSection.Card);
        // A definition for other text is not shown.
        Assert.DoesNotContain(device.Query(Asking(window, "define transient") with { Definition = new("ephemeral", entry) }).Groups,
            group => group.Section == PaletteSection.Card);
    }

    [Fact]
    public void ConversionsAndTheDictionaryEachTurnOff() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;

        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice =>
                    choice.Source == PaletteSource.Conversions || choice.Source == PaletteSource.Dictionary ? choice with { IsEnabled = false } : choice)]
            }
        }));
        Assert.DoesNotContain(device.Query(Asking(window, "5 km in miles")).Groups, group => group.Section == PaletteSection.Card);
        Assert.DoesNotContain(device.Query(Asking(window, "time in tokyo")).Groups, group => group.Section == PaletteSection.Card);
        Assert.Null(device.Query(Asking(window, "define ephemeral")).DefinitionTerm);
    }

    /// The card `answer` shows below the search.
    private static PaletteCard CardOf(PaletteAnswer answer) {
        int search = answer.Groups.ToList().FindIndex(group => group.Rows.Any(row => row.Kind == PaletteRowKind.Search));
        int card = answer.Groups.ToList().FindIndex(group => group.Section == PaletteSection.Card);
        Assert.True(card > search && search >= 0, "The card shows below the search.");
        return Assert.Single(answer.Groups[card].Rows).Card!;
    }
}
