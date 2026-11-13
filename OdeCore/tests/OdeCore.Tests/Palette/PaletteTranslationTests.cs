using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void ATranslationPhraseOffersAnInlineStateWithoutReplacingReturnSearchOrSendingSuggestions() {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            var answer = device.Query(Asking(window, "i want to eat food in french"));

            Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
            Assert.Contains(answer.Groups.SelectMany(group => group.Rows), row => row.Card?.Kind.Name == "translation");
            Assert.Null(answer.SuggestionAddress);
            Assert.Null(answer.WebLookup);
            Assert.Null(answer.DefinitionTerm);
        }
    }

    [Theory]
    [InlineData("i want to eat food in french", "i want to eat food", null, "fr")]
    [InlineData("translate bonjour to English", "bonjour", null, "en")]
    [InlineData("translate こんにちは into French", "こんにちは", null, "fr")]
    [InlineData("how do you say good morning in Spanish?", "good morning", null, "es")]
    [InlineData("translate bonjour from French to English", "bonjour", "fr", "en")]
    [InlineData("translate café 👋 into Japanese", "café 👋", null, "ja")]
    [InlineData("  TRANSLATE  hello!  INTO  FRENCH  ", "hello!", null, "fr")]
    [InlineData("“good morning” in German", "good morning", null, "de")]
    [InlineData("\"hello\" in Swedish", "hello", null, "sv")]
    [InlineData("translate café. to French", "café.", null, "fr")]
    [InlineData("hello in French", "hello", null, "fr")]
    [InlineData("good morning in Spanish", "good morning", null, "es")]
    [InlineData("thank you in Japanese", "thank you", null, "ja")]
    [InlineData("buenos días in Japanese", "buenos días", null, "ja")]
    [InlineData("你好 in English", "你好", null, "en")]
    [InlineData("news in French", "news", null, "fr")]
    [InlineData("restaurants in french", "restaurants", null, "fr")]
    [InlineData("movies in French", "movies", null, "fr")]
    public void TranslationGrammarPreservesThePhraseAndNeverInventsASource(string typed, string phrase, string? source, string target) {
        Assert.Equal(new PaletteTranslationLookup(phrase, source, target), TranslationLookup.Of(typed));
    }

    [Theory]
    [InlineData("weather tomorrow")]
    [InlineData("French restaurants")]
    [InlineData("how to learn French")]
    [InlineData("hotels in France")]
    [InlineData("i want food in France")]
    [InlineData("translate hello to Japan")]
    [InlineData("translate hello to fre")]
    [InlineData("translate to French")]
    [InlineData("translate hello from unknown to French")]
    [InlineData("how do you say hello in Canada")]
    [InlineData("https://example.test/?query=hello in french")]
    [InlineData("translate example.com to French")]
    [InlineData("translate a/b to French")]
    [InlineData("translate jane@example.test to French")]
    [InlineData("translate P@ssw0rd123 to French")]
    [InlineData("translate.google.com")]
    [InlineData("5 km in miles")]
    [InlineData("in French")]
    public void NearbySearchesAddressesCountriesAndIncompleteIntentsDoNotRequestTranslation(string typed) {
        Assert.Null(TranslationLookup.Of(typed));
    }

    [Theory]
    [InlineData("translate bonjour from French to French")]
    [InlineData("translate hello from English to Welsh")]
    [InlineData("how do you say hello in French")]
    public void ATranslationKeepsSearchFirstEvenWhenPageTranslationHowToAnswersMatch(string text) {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var answer = device.Query(Asking(device.Open(space), text));
        Assert.NotNull(answer.TranslationLookup);
        Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
    }

    [Fact]
    public void OnlyMatchingSuccessfulServiceOutputBecomesACopyableValue() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var question = Asking(device.Open(space), "translate hello to French");
        var lookup = device.Query(question).TranslationLookup!;
        Assert.NotNull(lookup);
        Assert.Null(CardOf(device.Query(question)).Value);
        var result = new PaletteTranslationResult(lookup, "en", "service-provided text", PaletteTranslationStatus.Translated);
        Assert.Equal(result.Text, CardOf(device.Query(question with { Translation = result })).Value);
        Assert.Null(CardOf(device.Query(question with { Translation = result with { Lookup = lookup with { Text = "different" } } })).Value);
        foreach (var status in PaletteTranslationStatus.All.Where(status => status != PaletteTranslationStatus.Translated)) {
            Assert.Null(CardOf(device.Query(question with { Translation = result with { Status = status } })).Value);
        }
        Assert.Null(CardOf(device.Query(question with { Translation = result with { Text = " " } })).Value);
    }

    [Fact]
    public void ExplicitProviderAndScopeDoNotInvokeAnUnrequestedLocalTranslationService() {
        var (session, space) = PaletteSession([]);
        using var device = new TestDevice(session);
        var question = Asking(device.Open(space), "translate hello to French");
        var provider = device.Authority.SearchCatalog.Resolving(BuiltInSearchProvider.YouTube);
        Assert.Null(device.Query(question with { Provider = provider }).TranslationLookup);
        Assert.Null(device.Query(question with { Scope = PaletteScope.History }).TranslationLookup);
    }

    [Theory]
    [InlineData("translate P@ssw0rd123 to French")]
    [InlineData("translate hello to fre")]
    [InlineData("translate example.com to French")]
    [InlineData("translate")]
    [InlineData("how do you say")]
    public void InvalidTranslationIntentNeverLeavesTheDeviceOrBecomesLearned(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var answer = device.Query(Asking(window, text) with { Remote = ["unexpected remote suggestion"] });
            Assert.Null(answer.TranslationLookup);
            Assert.Null(answer.GenerativeLookup);
            Assert.True(answer.KeepsQueryPrivate);
            Assert.Null(answer.SuggestionAddress);
            Assert.Null(answer.WebLookup);
            Assert.DoesNotContain(answer.Groups, group => group.Section == PaletteSection.SearchSuggestions);
            Assert.False(TranslationLookup.IsExplicit("translate.google.com"));
        }
    }

    [Fact]
    public void TranslationQueriesNeverBecomeLearnedChoicesEvenWhenSearchIsSelected() {
        var (session, space) = PaletteSession([], ("https://example.test/", "Destination", 1, 20, 10));
        using var app = new OdeApp();
        var workspace = TestWorkspaces.Open(app, session);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, CopyingWindowId: null, ShowingSpaceId: space,
            ShowingTabs: [], RestoresTabs: true));
        const string text = "i want to eat food in french";
        var destination = app.Query(Asking(window, "Destination")).Groups.SelectMany(group => group.Rows)
            .First(row => row.Kind == PaletteRowKind.History);
        foreach (var prompt in new[] { text, "translate P@ssw0rd123 to French", "translate hello to fre" }) {
            app.Send(new RecordPaletteChoice(window, prompt, destination));
            app.Send(new RecordPaletteChoice(window, prompt, destination));
        }
        Assert.Empty(app.Device.MemoryOf(space).Choices);
        Assert.Empty(app.Device.MemoryOf(space).Places);
        app.Send(new RecordPaletteChoice(window, "ordinary search", destination));
        Assert.Single(app.Device.MemoryOf(space).Choices);
    }
}
