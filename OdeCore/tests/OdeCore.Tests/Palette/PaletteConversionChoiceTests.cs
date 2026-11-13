using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// Incomplete conversion questions offer bounded, dimensionally honest local
/// answers without replacing search, a leading tab, or an entered scope.
public sealed partial class BrowserContractsTests {
    #region Actions - Conversion Choices

    [Fact]
    public void AnIncompleteOunceQuestionSeparatesWeightFromUSFluidVolumeAndEachRowOwnsItsCopyValue() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var answer = device.Query(Asking(device.Open(space), "how many oz in a"));
        var rows = answer.Groups.Single(group => group.Section == PaletteSection.Card).Rows;

        Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
        Assert.InRange(rows.Count, 2, 4);
        Assert.Contains(rows, row => row.Card is { Value: "16", Title: "16 ounces (weight)", Subtitle: "1 pound =" });
        Assert.Contains(rows, row => row.Card is { Value: "8", Title: "8 US fluid ounces", Subtitle: "1 US cup =" });
        Assert.Equal(rows.Count, rows.Distinct().Count());
        Assert.All(rows, row => {
            Assert.Equal(PaletteActivation.RunsCard, row.Kind.Activation);
            Assert.True(row.Card!.Kind.CopiesValue);
            Assert.NotNull(row.Card.Value);
            Assert.Null(row.Address);
        });
        Assert.Null(answer.DefinitionTerm);
        Assert.Null(answer.WebLookup);
    }

    [Theory]
    [InlineData("how many oz in a po", "1 pound =", "16")]
    [InlineData("how many oz in 2 po", "2 pounds =", "32")]
    [InlineData("how many oz in -2 po", "-2 pounds =", "-32")]
    [InlineData("how many cm in a ya", "1 yard =", "91.44")]
    [InlineData("how many cm in a me", "1 meter =", "100")]
    [InlineData("how many cm are in 2 me", "2 meters =", "200")]
    [InlineData("how many cm in 2,5 me", "2.5 meters =", "250")]
    [InlineData("how many fluid ounces in a US cu", "1 US cup =", "8")]
    [InlineData("HOW MANY CM IN A ME", "1 meter =", "100")]
    public void ConversionChoicesFilterUnitPrefixesAndKeepTheActualAmount(string text, string subtitle, string value) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var answer = device.Query(Asking(device.Open(space), text));
        var row = Assert.Single(answer.Groups.Single(group => group.Section == PaletteSection.Card).Rows);

        Assert.Equal((subtitle, value), (row.Card!.Subtitle, row.Card.Value));
    }

    [Fact]
    public void LengthChoicesUseCompatibleCatalogUnitsAndBoundTheList() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var rows = device.Query(Asking(device.Open(space), "how many cm in a")).Groups
            .Single(group => group.Section == PaletteSection.Card).Rows;

        Assert.InRange(rows.Count, 2, 4);
        Assert.Contains(rows, row => row.Card is { Value: "100", Title: "100 centimeters", Subtitle: "1 meter =" });
        Assert.Contains(rows, row => row.Card is { Value: "30.48", Title: "30.48 centimeters", Subtitle: "1 foot =" });
        Assert.All(rows, row => Assert.EndsWith("centimeters", row.Card!.Title));
    }

    [Theory]
    [InlineData("how many oz in a word")]
    [InlineData("how many ounces in a poundcake")]
    [InlineData("how many ounces in a pound cake")]
    [InlineData("how many oz in a cup")]
    [InlineData("how many oz in a US cup")]
    [InlineData("how many oz in a cup of coffee")]
    [InlineData("how many cm in a kg")]
    [InlineData("how many cm in a cm")]
    [InlineData("cup of coffee")]
    [InlineData("ounces of gold price")]
    [InlineData("oz")]
    [InlineData("cm")]
    [InlineData("a")]
    [InlineData("how many o in a")]
    [InlineData("how many oz in apple")]
    [InlineData("https://example.org/how many oz in a")]
    [InlineData("example.org how many oz in a")]
    [InlineData("how many oz in a po/website")]
    [InlineData("how many oz in a imperial cup")]
    public void UnfinishedProseAndIncompatibleCompleteQuestionsDoNotBecomeConversionChoices(string text) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var answer = device.Query(Asking(device.Open(space), text));
        Assert.DoesNotContain(answer.Groups, group => group.Section == PaletteSection.Card);
    }

    [Fact]
    public void ConversionChoicesRespectOptOutProvidersAndEveryEnteredScope() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        var question = Asking(window, "how many oz in a");
        var provider = device.Query(Asking(window, "yt")).OfferedSearch!.Provider;

        Assert.DoesNotContain(device.Query(question with { Provider = provider }).Groups, group => group.Section == PaletteSection.Card);
        foreach (var scope in PaletteScope.All)
            Assert.DoesNotContain(device.Query(question with { Scope = scope }).Groups, group => group.Section == PaletteSection.Card);
        foreach (string entered in new[] { "$yt how many oz in a", "@tabs how many oz in a" })
            Assert.DoesNotContain(device.Query(question with { Text = entered }).Groups, group => group.Section == PaletteSection.Card);

        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;
        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice => choice.Source == PaletteSource.Conversions
                    ? choice with { IsEnabled = false } : choice)]
            }
        }));
        Assert.DoesNotContain(device.Query(question).Groups, group => group.Section == PaletteSection.Card);
    }

    [Fact]
    public void ConversionChoicesStayLocalInPrivateWindowsAndCannotReplaceAStrongTabLead() {
        const string text = "how many oz in a";
        var (target, shown) = (Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(target, text, "https://notes.example.org/"),
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.org/")]);
        using var device = new TestDevice(session, WorkspaceKind.Private);
        var window = device.Open(space, (space, shown));
        device.Send(new SetSearchSuggestions(true));
        var privateAnswer = device.Query(Asking(window, "how many cm in a"));
        Assert.InRange(privateAnswer.Groups.Single(group => group.Section == PaletteSection.Card).Rows.Count, 2, 4);
        Assert.Null(privateAnswer.SuggestionAddress);
        Assert.Null(privateAnswer.WebLookup);
        Assert.Null(privateAnswer.DefinitionTerm);

        var answer = device.Query(Asking(window, text));

        Assert.Equal(target, answer.Groups[0].Rows[0].TabId);
        Assert.Equal(PaletteRowKind.Search, answer.Groups.SelectMany(group => group.Rows).Single(row => row.Kind == PaletteRowKind.Search).Kind);
        Assert.InRange(answer.Groups.Single(group => group.Section == PaletteSection.Card).Rows.Count, 2, 4);
        Assert.Null(answer.SuggestionAddress);
        Assert.Null(answer.WebLookup);
        Assert.Null(answer.DefinitionTerm);
    }

    [Fact]
    public void ConversionChoicesRespectTheExistingInputLengthAndFiniteValueBounds() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var window = device.Open(space);
        foreach (string text in new[] { "how many oz in a " + new string('p', 81), "how many cm in " + new string('9', 81) + " me",
            "how many cm in NaN me", "how many cm in Infinity me", "how many cm in 1e999 me" })
            Assert.DoesNotContain(device.Query(Asking(window, text)).Groups, group => group.Section == PaletteSection.Card);
    }
    #endregion
}
