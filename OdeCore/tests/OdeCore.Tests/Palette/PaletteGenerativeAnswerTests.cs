using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("why is the sky blue?")]
    [InlineData("ask ode explain photosynthesis")]
    [InlineData("rewrite: I cannot attend the meeting today")]
    [InlineData("rewrite: I have 2 cups of coffee and need to leave now")]
    public void PrivatePreviewWithholdsEveryRemoteLookupAndNeverReplacesReturn(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var question = Asking(window, text) with { Remote = ["unwanted remote answer"] };
            var answer = device.Query(question);
            Assert.NotNull(answer.GenerativeLookup);
            Assert.True(answer.KeepsQueryPrivate);
            Assert.Equal(PaletteRowKind.Search, answer.Groups[0].Rows[0].Kind);
            Assert.Null(answer.SuggestionAddress);
            Assert.Null(answer.WebLookup);
            Assert.Null(answer.DefinitionTerm);
            Assert.DoesNotContain(answer.Groups, group => group.Section == PaletteSection.SearchSuggestions);
            var lookup = answer.GenerativeLookup!;
            var result = new PaletteGenerativeResult(lookup, "Actual service output", PaletteGenerativeStatus.Answered);
            Assert.Equal(result.Text, CardOf(device.Query(question with { Generative = result })).Value);
            Assert.Null(CardOf(device.Query(question with { Generative = result with { Lookup = new("a different prompt") } })).Value);
            foreach (var status in PaletteGenerativeStatus.All.Where(status => status != PaletteGenerativeStatus.Answered))
                Assert.Null(CardOf(device.Query(question with { Generative = result with { Status = status } })).Value);
            Assert.Null(CardOf(device.Query(question with { Generative = result with { Text = " " } })).Value);
            Assert.Null(CardOf(device.Query(question with { Generative = result with { Text = new('x', 1_201) } })).Value);
        }
    }

    [Theory]
    [InlineData("")]
    [InlineData("https://example.test/why is the sky blue")]
    [InlineData("ask ode explain example.com")]
    [InlineData("ask ode explain localhost:3000/test")]
    [InlineData("ask ode rewrite jane@example.test")]
    [InlineData("ask ode explain my password hunter2")]
    [InlineData("ask ode ")]
    [InlineData("ask")]
    [InlineData("ask o")]
    [InlineData("ask od")]
    [InlineData("ask ode explain hunter2!x")]
    [InlineData("ask ode explain ghp_0123456789abcdefABCDEF0123456789")]
    [InlineData("$g why is the sky blue?")]
    [InlineData("@history why is the sky blue?")]
    [InlineData("24 * 7")]
    [InlineData("ask ode 24 * 7")]
    [InlineData("32oz")]
    [InlineData("how many oz in a po")]
    [InlineData("define ephemeral")]
    [InlineData("translate hello to French")]
    [InlineData("how do I split view")]
    [InlineData("ask ode how do I split view")]
    public void PrivatePreviewDoesNotInterceptNavigationScopesSecretsOrExistingAnswers(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var answer = device.Query(Asking(window, text));
            Assert.Null(answer.GenerativeLookup);
            if (GenerativeAnswerLookup.KeepsPrivate(text, device.Authority.Current.AppPreferences!.Palette)) {
                Assert.True(answer.KeepsQueryPrivate);
                Assert.Null(answer.SuggestionAddress);
                Assert.Null(answer.WebLookup);
            }
        }
    }

    [Theory]
    [InlineData("rewrite", "rewrite")]
    [InlineData("rephrase", "rephrase")]
    [InlineData("proofread", "proofread")]
    [InlineData("summarize", "summarize")]
    [InlineData("shorten", "shorten")]
    [InlineData("rewrite hi")]
    [InlineData("rephrase hi")]
    [InlineData("proofread hi")]
    [InlineData("summarize hi")]
    [InlineData("shorten hi")]
    [InlineData("rewrite:")]
    [InlineData("rephrase:")]
    [InlineData("proofread:")]
    [InlineData("summarize:")]
    [InlineData("shorten:")]
    [InlineData("rewrite: hi")]
    [InlineData("  RePhRaSe : hi  ")]
    [InlineData("proofread\thi")]
    [InlineData("summarize\nhi")]
    [InlineData("rewrite my password hunter2")]
    [InlineData("rephrase jane@example.test")]
    [InlineData("proofread https://example.test/draft")]
    [InlineData("summarize my api key")]
    [InlineData("shorten secret=value")]
    public void IneligibleRewriteIntentStillWithholdsRemoteLookups(string text, string? localDefinition = null) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var answer = device.Query(Asking(window, text) with { Remote = ["unwanted remote answer"] });
            Assert.Null(answer.GenerativeLookup);
            Assert.True(answer.KeepsQueryPrivate);
            Assert.Null(answer.SuggestionAddress);
            Assert.Null(answer.WebLookup);
            Assert.Equal(localDefinition, answer.DefinitionTerm);
            Assert.DoesNotContain(answer.Groups, group => group.Section == PaletteSection.SearchSuggestions);
        }
    }

    [Fact]
    public void PrivatePreviewIsOptInAndAnExplicitProviderOrScopeNeverInvokesIt() {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            var question = Asking(window, "why is the sky blue?");
            Assert.Null(device.Query(question).GenerativeLookup);
            Assert.False(PalettePreferences.Default.Offers(PaletteSource.AskOde));
            foreach (var text in new[] { "rewrite", "rewrite hi", "rephrase hi", "proofread hi", "summarize hi", "shorten hi", "ask od" }) {
                var ordinary = device.Query(Asking(window, text));
                Assert.False(ordinary.KeepsQueryPrivate);
                Assert.Null(ordinary.GenerativeLookup);
                Assert.NotNull(ordinary.SuggestionAddress);
            }
            EnablePrivateAnswers(device);
            Assert.Null(device.Query(question with { Scope = PaletteScope.History }).GenerativeLookup);
            Assert.Null(device.Query(question with { Provider = device.Authority.SearchCatalog.Default }).GenerativeLookup);
            foreach (var text in new[] { "ordinary search", "rewritten article", "rephrased article", "proofreader jobs", "summarized article", "shortened article" }) {
                var ordinary = device.Query(Asking(window, text));
                Assert.True(ordinary.KeepsQueryPrivate);
                Assert.NotNull(ordinary.GenerativeLookup);
                Assert.Null(ordinary.SuggestionAddress);
                Assert.Null(ordinary.WebLookup);
            }
            Assert.Equal(PaletteScope.Help, device.Query(Asking(window, "ode")).OfferedScope);
            Assert.Equal(PaletteCardKind.Calculation, CardOf(device.Query(Asking(window, "ask ode 24 * 7"))).Kind);
            Assert.Equal(PaletteRowKind.Answer, device.Query(Asking(window, "ask ode how do I split view")).Groups[0].Rows[0].Kind);
        }
    }

    [Theory]
    [InlineData("persistent")]
    [InlineData("private")]
    public void PrivatePreviewUsesOnlyTypedTextInEitherWorkspaceAndNeverLearnsEvenANeighboringSearch(string kind) {
        var (session, space) = PaletteSession([], ("https://example.test/", "Destination", 1, 20, 10));
        using var app = new OdeApp();
        var persistent = TestWorkspaces.Open(app, session);
        var preferences = AppPreferences.Default;
        app.Send(new SetAppPreferences(persistent, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice => choice.Source == PaletteSource.AskOde
                    ? choice with { IsEnabled = true } : choice)]
            }
        }));
        var workspace = kind == "persistent" ? persistent : TestWorkspaces.Open(app, session.DeepClone(), WorkspaceKind.Private);
        var window = Guid.NewGuid();
        var viewedSpace = app.Workspace(workspace).Current.Spaces[0].Id;
        app.Send(new OpenWindow(window, workspace, Saved: false, CopyingWindowId: null, ShowingSpaceId: viewedSpace,
            ShowingTabs: [], RestoresTabs: true));
        var answer = app.Query(Asking(window, "why is the sky blue?"));
        Assert.Equal(new PaletteGenerativeLookup("why is the sky blue?"), answer.GenerativeLookup);
        var persistentWindow = Guid.NewGuid();
        app.Send(new OpenWindow(persistentWindow, persistent, Saved: false, CopyingWindowId: null, ShowingSpaceId: space,
            ShowingTabs: [], RestoresTabs: true));
        var destination = app.Query(Asking(persistentWindow, "Destination")).Groups.SelectMany(group => group.Rows)
            .First(row => row.Kind == PaletteRowKind.History);
        foreach (var prompt in new[] { "why is the sky blue?", "ask ode explain my password hunter2", "rewrite", "rewrite hi", "rewrite:",
            "grams to tsp", "5 grams to tsp", "ask ode 5 grams to tsp", "5 tsp to grams", "how many oz in a cup", "how many oz in a US cup" }) {
            app.Send(new RecordPaletteChoice(window, prompt, destination));
            app.Send(new RecordPaletteChoice(window, prompt, destination));
        }
        Assert.Empty(app.Device.MemoryOf(space).Choices);
        Assert.Empty(app.Device.MemoryOf(space).Places);
        if (kind == "persistent") {
            app.Send(new RecordPaletteChoice(window, "ordinary search", destination));
            Assert.Empty(app.Device.MemoryOf(space).Choices);
        }
    }

    [Theory]
    [InlineData("What remains after taking 12.5 percent off 80?", "80-12.5", null)]
    [InlineData("What remains after taking 12.5 percent off 80?", "12.5% off 80", "70")]
    [InlineData("Take 15 percent off 60", "60-15", null)]
    [InlineData("Take 15 percent off 60", "60+15", null)]
    [InlineData("Take 15 percent off 60", "15*60", null)]
    [InlineData("Take 15 percent off 60", "15%60", null)]
    [InlineData("Take 15 percent off 60", "15% of 60", null)]
    [InlineData("Take 15 percent off 60", "15% off 60", "51")]
    [InlineData("Take 15 percent off 60", "60% off 15", null)]
    [InlineData("Take fifteen percent off sixty", "60% off 15", null)]
    [InlineData("Take fifteen percent off sixty", "15% off 60", "51")]
    [InlineData("Take -15 percent off 60", "-15% off 60", "69")]
    [InlineData("Find 15 percent of 60", "60% of 15", null)]
    [InlineData("Take 15 percent off 60 and 5 percent off 20", "15% off 60", null)]
    [InlineData("Find 15 percent of 60", "15*60", null)]
    [InlineData("Find 15 percent of 60", "15% off 60", null)]
    [InlineData("Find 15 percent of 60", "15% of 60", "9")]
    [InlineData("Take 15% off 60", "60-15", null)]
    [InlineData("Find the remainder of 60 divided by 15", "60%15", "0")]
    [InlineData("Multiply negative six by eight", "-6*8", "-48")]
    [InlineData("Multiply positive six by eight", "6*8", "48")]
    [InlineData("Multiply minus six by eight", "-6*8", "-48")]
    [InlineData("Multiply -twenty by four please", "-20*4", "-80")]
    [InlineData("Multiply negative-six by eight", "-6*8", "-48")]
    [InlineData("Multiply negative one hundred by eight", "-1*8", null)]
    [InlineData("Work out the product of twelve and four", "12 * 4", "48")]
    [InlineData("Work out the product of 17 and 19", "17 * 19", "323")]
    [InlineData("Work out the product of 17 and 19", "17 * 29", null)]
    [InlineData("Work out the product of 17 and 19", "17 * 17", null)]
    [InlineData("Could you divide 9 by 0 for me?", "9 / 0", null)]
    [InlineData("Multiply -3 by 4 please", "-3 * 4", "-12")]
    [InlineData("Multiply -3 by 4 please", "3 * 4", null)]
    [InlineData("Multiply 3 by 4 please", "-3 * 4", null)]
    [InlineData("Subtract 4 from 3 please", "3 - 4", "-1")]
    [InlineData("what is 5 minus 2", "5 - 2", "3")]
    [InlineData("what is 2 plus 3", "2 + 3", "5")]
    [InlineData("Please calculate 3 + 4", "3+4", "7")]
    [InlineData("Please calculate 3 - 4", "3-4", "-1")]
    [InlineData("Please calculate 3 +4", "3+4", "7")]
    [InlineData("Please calculate 3 -4", "3-4", "-1")]
    [InlineData("Please calculate 3 - -4", "3- -4", "7")]
    [InlineData("Please calculate 3 - - 4", "3- -4", "7")]
    [InlineData("Multiply +4 by 3 please", "4*3", "12")]
    [InlineData("Multiply -4 by 3 please", "-4*3", "-12")]
    [InlineData("Multiply - 4 by 3 please", "-4*3", "-12")]
    [InlineData("Multiply - 4 by 3 please", "4*3", null)]
    [InlineData("Please calculate 3 + 4", "3+3", null)]
    [InlineData("Please calculate 3 - 4", "3-5", null)]
    [InlineData("Multiply .5 by 4 please", "5 * 4", null)]
    [InlineData("Multiply 1e-3 by 4 please", "3 * 4", null)]
    [InlineData("Multiply 1 000 by 4 please", "1 * 4", null)]
    [InlineData("Multiply one hundred by four please", "1 * 4", null)]
    [InlineData("Multiply one million and four by two please", "4 * 2", null)]
    [InlineData("Multiply −3 by 4 please", "3 * 4", null)]
    [InlineData("Multiply 3 by 4 please", "٣ * 4", null)]
    [InlineData("Multiply .5 by 4 please", ".5 * 4", "2")]
    [InlineData("Multiply 1 000 by 4 please", "1000 * 4", "4000")]
    public void SemanticArithmeticChecksGroundedOperandsBeforeProducingCopyValue(string text, string expression, string? expected) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var question = Asking(window, text);
            var initial = device.Query(question);
            Assert.True(initial.KeepsQueryPrivate);
            Assert.Null(initial.SuggestionAddress);
            var lookup = Assert.IsType<PaletteGenerativeLookup>(initial.GenerativeLookup);
            var interpretation = new PaletteInterpretation(PaletteInterpretationKind.Calculation, expression, null, null, null, null);
            var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered, interpretation);
            var answer = device.Query(question with { Generative = result });
            Assert.Equal(initial.Groups[0].Rows[0], answer.Groups[0].Rows[0]);
            Assert.Equal(expected, answer.Groups.SelectMany(group => group.Rows).Select(row => row.Card?.Value).FirstOrDefault(value => value is not null));
            Assert.DoesNotContain(device.Query(question with { Generative = result with { Lookup = new("different edit") } }).Groups
                .SelectMany(group => group.Rows), row => row.Card?.Value is not null);
            Assert.DoesNotContain(device.Query(question with { Generative = new(lookup, "An unchecked number", PaletteGenerativeStatus.Answered) }).Groups
                .SelectMany(group => group.Rows), row => row.Card?.Value is not null);
        }
    }

    [Theory]
    [InlineData("Express 6 kilometres in metres please", "6", "metres", "kilometres", null, null)]
    [InlineData("Express 6 kilometres in metres please", "6", "kilometres", "metres", null, "6000")]
    [InlineData("Express 6 kilometres in metres, rounded to 2 decimals please", "2", "kilometres", "metres", null, null)]
    [InlineData("Express 6 kilometres in metres, rounded to 2 decimals please", "6", "kilometres", "metres", null, "6000")]
    [InlineData("Express 6 metres in metres please", "6", "metres", "metres", null, "6")]
    [InlineData("Please express metres in kilometres", "1", "metres", "kilometres", null, null)]
    [InlineData("Express 6 kilometres and 2 metres in feet please", "6", "kilometres", "feet", null, null)]
    [InlineData("Express 6 kilometres or miles in metres please", "6", "kilometres", "metres", null, null)]
    [InlineData("Express 6 kilometres in metres and feet please", "6", "kilometres", "metres", null, null)]
    [InlineData("Express 6 metres in metres please", "6 metres", "metres", "metres", null, "6")]
    [InlineData("Express 6 metres in metres please", null, "metres", "metres", null, null)]
    [InlineData("Express 6 kilometres in metres please", "6000", "kilometres", "metres", null, null)]
    [InlineData("Express negative six metres in feet please", "negative six", "metres", "feet", null, "-19.69")]
    [InlineData("Express my 7.25 kilometre route in metres please", "7.25", "kilometre", "metres", null, "7250")]
    [InlineData("Please express twelve pounds as ounces", "twelve", "pounds", "ounces", null, "192")]
    [InlineData("Please express twelve pounds as ounces", "twelve pounds", "pound", "ounce", null, "192")]
    [InlineData("What's a pound worth in ounces?", "1", "pound", "ounce", null, "16")]
    [InlineData("Please express twelve pounds as ounces", "twelve", "kilograms", "ounce", null, null)]
    [InlineData("Please express twelve pounds as ounces", "four", "pounds", "ounces", null, null)]
    [InlineData("Please express twelve pounds as ounces", null, "pounds", "ounces", null, null)]
    [InlineData("Change 1 Imperial pint into millilitres", "1", "pint", "millilitres", null, null)]
    [InlineData("Tell me how many teaspoons 25 grams of water would fill", "25", "grams", "teaspoons", "water", null)]
    [InlineData("How much is 8 oz in cups?", "8", "oz", "cups", null, null)]
    [InlineData("Please express 8 fluid ounces as pounds", "8", "ounces", "pounds", null, null)]
    [InlineData("Please express 8 fl. oz as pounds", "8", "oz", "pounds", null, null)]
    [InlineData("Please express 8 fl. oz. as pounds", "8", "oz", "pounds", null, null)]
    [InlineData("Please express 8 US fl. oz as pounds", "8", "oz", "pounds", null, null)]
    [InlineData("Please express 8 fl. oz as pounds", "8", "fl. oz", "pounds", null, null)]
    [InlineData("Please express 8 fl. oz as ml", "8", "fl. oz", "ml", null, "236.6")]
    [InlineData("Please express 8 oz as pounds", "8", "oz", "pounds", null, "0.5")]
    [InlineData("Please express 8 nautical miles as meters", "8", "miles", "meters", null, null)]
    [InlineData("Please express -3 pounds as ounces", "3", "pounds", "ounces", null, null)]
    [InlineData("Please express -3 pounds as ounces", "3 pounds", "pounds", "ounces", null, null)]
    [InlineData("Please express 0.5 pounds as ounces", "5", "pounds", "ounces", null, null)]
    [InlineData("Please express 1,000 pounds as ounces", "000", "pounds", "ounces", null, null)]
    [InlineData("Please express one hundred pounds as ounces", "one", "pounds", "ounces", null, null)]
    [InlineData("Please express -3 pounds as ounces", "-3 pounds", "pounds", "ounces", null, "-48")]
    [InlineData("Please express 8 troy ounces as pounds", "8", "ounces", "pounds", null, null)]
    [InlineData("Please express 8 fluid oz as pounds", "8", "oz", "pounds", null, null)]
    [InlineData("Please express 8 cubic meters as feet", "8", "meters", "feet", null, null)]
    [InlineData("Please express 8 nautical miles as meters", "8", "nautical miles", "meters", null, "14816")]
    [InlineData("Please express - 3 pounds as ounces", "3", "pounds", "ounces", null, null)]
    [InlineData("Please express 1'000 pounds as ounces", "000", "pounds", "ounces", null, null)]
    public void SemanticConversionUsesOnlyQuotedInputsAndNeverGuessesDensity(string text, string? amount, string from, string to,
        string? ingredient, string? expected) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var question = Asking(window, text);
            var lookup = Assert.IsType<PaletteGenerativeLookup>(device.Query(question).GenerativeLookup);
            var interpretation = new PaletteInterpretation(PaletteInterpretationKind.Conversion, null, amount, from, to, ingredient);
            var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered, interpretation);
            var answer = device.Query(question with { Generative = result });
            Assert.True(answer.KeepsQueryPrivate);
            Assert.Equal(expected, answer.Groups.SelectMany(group => group.Rows).Select(row => row.Card?.Value).FirstOrDefault(value => value is not null));
            var preferences = device.Authority.Current.AppPreferences!;
            device.Send(new SetAppPreferences(device.Workspace, preferences with {
                Palette = preferences.Palette with {
                    Sources = [.. preferences.Palette.Sources.Select(choice => choice.Source == PaletteSource.Conversions
                        ? choice with { IsEnabled = false } : choice)]
                }
            }));
            Assert.DoesNotContain(device.Query(question with { Generative = result }).Groups.SelectMany(group => group.Rows),
                row => row.Card?.Value is not null);
        }
    }

    [Theory]
    [InlineData("what is photosynthesis in plants")]
    [InlineData("how do I spend time in nature")]
    [InlineData("what is a plant")]
    [InlineData("ask ode explain photosynthesis")]
    public void GeneralTextRetainsRequestAuthorizationWithoutNumericFallback(string text) {
        var lookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of(text));
        Assert.Equal(GenerativeAnswerLookup.IsExplicit(text), lookup.IsExplicitRequest);
        var result = new PaletteGenerativeResult(lookup, "A general explanation", PaletteGenerativeStatus.Answered);
        Assert.Equal(result.Text, GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text)?.Value);
    }

    [Theory]
    [InlineData("ask ode m to t")]
    [InlineData("ask ode oz in lb")]
    [InlineData("ask ode 3 m")]
    [InlineData("ask ode multiply 3 by 4")]
    [InlineData("ask ode explain 1e-3")]
    public void ExplicitNumericRequestsCannotUseGeneratedProse(string text) {
        var lookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of(text));
        var result = new PaletteGenerativeResult(lookup, "Unchecked numerical answer", PaletteGenerativeStatus.Answered);
        Assert.Null(GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text));
    }

    [Fact]
    public void ExplicitAuthorizationSurvivesPrefixStrippingAndLookupMatching() {
        var explicitLookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of("ask ode explain photosynthesis"));
        var ordinaryLookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of("explain photosynthesis"));
        Assert.Equal(ordinaryLookup.Text, explicitLookup.Text);
        Assert.NotEqual(ordinaryLookup, explicitLookup);
        var result = new PaletteGenerativeResult(ordinaryLookup, "Unscoped result", PaletteGenerativeStatus.Answered);
        Assert.Null(GenerativeAnswerLookup.Card(explicitLookup, result, PalettePreferences.Default,
            "ask ode explain photosynthesis")?.Value);
    }

    [Theory]
    [InlineData("Multiply negative three by four please", "3 * 4")]
    [InlineData("Multiply negative-three by four please", "3 * 4")]
    [InlineData("Multiply -twenty by four please", "20 * 4")]
    [InlineData("Multiply - three by four please", "3 * 4")]
    [InlineData("Multiply minus three by four please", "3 * 4")]
    public void SignedWordsCannotAuthorizePositiveOperands(string text, string expression) {
        var lookup = new PaletteGenerativeLookup(text);
        var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered,
            new(PaletteInterpretationKind.Calculation, expression, null, null, null, null));
        Assert.Null(GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text));
    }

    [Fact]
    public void ImplicitNoAnswerAndUnavailableStayPrivateWithoutStatusCards() {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var question = Asking(window, "ordinary search prose") with { Remote = ["unwanted remote suggestion"] };
            var initial = device.Query(question);
            var lookup = Assert.IsType<PaletteGenerativeLookup>(initial.GenerativeLookup);
            foreach (var status in PaletteGenerativeStatus.All) {
                var result = new PaletteGenerativeResult(lookup, null, status,
                    new(PaletteInterpretationKind.NoAnswer, null, null, null, null, null));
                var answer = device.Query(question with { Generative = result });
                Assert.True(answer.KeepsQueryPrivate);
                Assert.Null(answer.SuggestionAddress);
                Assert.Null(answer.WebLookup);
                Assert.DoesNotContain(answer.Groups, group => group.Section == PaletteSection.Card || group.Section == PaletteSection.SearchSuggestions);
                Assert.Equal(initial.Groups[0].Rows[0], answer.Groups[0].Rows[0]);
            }
        }
    }

    [Fact]
    public void LockedSpaceCannotAuthorizePrivateGeneration() {
        var session = GuardedSession();
        var identity = Identity(session);
        using var device = new TestDevice(session);
        EnablePrivateAnswers(device);
        Assert.Null(device.Query(Asking(device.Open(identity.Space), "why is the sky blue?")).GenerativeLookup);
    }

    private static void EnablePrivateAnswers(TestDevice device) {
        var preferences = device.Authority.Current.AppPreferences ?? AppPreferences.Default;
        device.Send(new SetAppPreferences(device.Workspace, preferences with {
            Palette = preferences.Palette with {
                Sources = [.. preferences.Palette.Sources.Select(choice => choice.Source == PaletteSource.AskOde
                    || choice.Source == PaletteSource.WebAnswers ? choice with { IsEnabled = true } : choice)]
            }
        }));
    }
}
