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
    [InlineData("why example.test fails")]
    [InlineData("what example.test means")]
    [InlineData("how example.test works")]
    [InlineData("when jane@example.test replies")]
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
            foreach (var text in new[] { "rewrite", "rewrite hi", "rephrase hi", "proofread hi", "summarize hi", "shorten hi", "ask od",
                "why example.test fails", "what example.test means", "how example.test works" }) {
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
            foreach (var text in new[] { "https://example.test", "example.test troubleshooting" }) {
                var ordinary = device.Query(Asking(window, text));
                Assert.False(ordinary.KeepsQueryPrivate);
                Assert.Null(ordinary.GenerativeLookup);
                Assert.NotEmpty(ordinary.Groups);
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
        session["spaces"]![0]!["browsingPreferences"]!["searchSuggestionsEnabled"] = true;
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
            "why example.test fails", "what example.test means", "how example.test works", "when jane@example.test replies",
            "grams to tsp", "5 grams to tsp", "ask ode 5 grams to tsp", "5 tsp to grams", "how many oz in a cup", "how many oz in a US cup" }) {
            var preview = app.Query(Asking(window, prompt) with { Remote = ["unwanted remote answer"] });
            Assert.True(preview.KeepsQueryPrivate);
            Assert.Null(preview.SuggestionAddress);
            Assert.Null(preview.WebLookup);
            Assert.DoesNotContain(preview.Groups, group => group.Section == PaletteSection.SearchSuggestions);
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
    [InlineData("What remains after taking 12.5 percent off 80?", "80 - 12.5% of 80", "70")]
    [InlineData("What remains after taking 12.5 percent off 80?", "80 - 12.5% of 81", null)]
    [InlineData("What remains after taking 12.5 percent off 80?", "80 - 12.5% of 80 + 80", null)]
    [InlineData("Split 84 into seven equal parts", "84+84+84+84+84+84+84", null)]
    [InlineData("Find the sum of 15 and 60", "15% of 60", null)]
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
    [InlineData("Multiply -(3) by 4 please", "3*4", null)]
    [InlineData("Multiply -((3)) by 4 please", "3*4", null)]
    [InlineData("Multiply negative (3) by 4 please", "3*4", null)]
    [InlineData("Multiply -(2 + 3) by 4 please", "3*4", null)]
    [InlineData("Multiply (- (3)) by 4 please", "3*4", null)]
    [InlineData("Multiply −[3] by 4 please", "3*4", null)]
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
    [InlineData("I'm measuring 3 pounds; tell me the equivalent weight in ounces", "3 pounds", "pound", "ounce", null, "48")]
    [InlineData("The room reads 72 Fahrenheit; express that in Celsius", "72 Fahrenheit", "Fahrenheit", "Celsius", null, "22.22")]
    [InlineData("I am measuring 3 pounds; show me the equivalent weight in ounces please", "3", "pounds", "ounces", null, "48")]
    [InlineData("I am reading 20 meters; tell me the equivalent distance in feet", "20", "meters", "feet", null, "65.62")]
    [InlineData("I am measuring 48 ounces, tell me the equivalent weight in pounds", "48", "ounces", "pounds", null, "3")]
    [InlineData("I am measuring double 48 ounces, tell me the equivalent weight in pounds", "48", "ounces", "pounds", null, null)]
    [InlineData("I am measuring 48 ounces, tell me the equivalent weight in pounds, then halve it", "48", "ounces", "pounds", null, null)]
    [InlineData("I am measuring 48 ounces, tell me the equivalent weight in pounds", "48", "pounds", "ounces", null, null)]
    [InlineData("My kitchen thermometer is reading 72 Fahrenheit; show me the equivalent temperature in Celsius", "72", "Fahrenheit", "Celsius", null, "22.22")]
    [InlineData("I'm measuring double 3 pounds; tell me the equivalent weight in ounces", "3", "pounds", "ounces", null, null)]
    [InlineData("I am reading half of 20 meters; show me the equivalent distance in feet", "20", "meters", "feet", null, null)]
    [InlineData("I'm measuring 3 pounds divided by 2; tell me the equivalent weight in ounces", "3", "pounds", "ounces", null, null)]
    [InlineData("The room reads 72 Fahrenheit; express that in Celsius divided by 2", "72", "Fahrenheit", "Celsius", null, null)]
    [InlineData("I'm measuring 3 pounds; tell me the equivalent weight in ounces, then halve it", "3", "pounds", "ounces", null, null)]
    [InlineData("The room reads 72 Fahrenheit; express half of that in Celsius", "72", "Fahrenheit", "Celsius", null, null)]
    [InlineData("I have 32 US fluid ounces; how many US cups is that?", "32", "fluid ounces", "cups", null, "4")]
    [InlineData("I have 32 US fluid ounces; how many US cups is that?", "32", "cups", "fluid ounces", null, null)]
    [InlineData("I have 32 US fluid ounces and US cups", "32", "fluid ounces", "cups", null, null)]
    [InlineData("I have 32 US fluid ounces; how many US cups or pints is that?", "32", "fluid ounces", "cups", null, null)]
    [InlineData("Express 6 kilometres in metres please", "6", "metres", "kilometres", null, null)]
    [InlineData("Express 6 kilometres in metres please", "6", "kilometres", "metres", null, "6000")]
    [InlineData("Express 6 kilometres in metres, rounded to 2 decimals please", "2", "kilometres", "metres", null, null)]
    [InlineData("Express 6 kilometres in metres, rounded to 2 decimals please", "6", "kilometres", "metres", null, "6000")]
    [InlineData("Convert 50 percent of 20 meters to feet", "20", "meters", "feet", null, null)]
    [InlineData("Convert 50% of 20 meters to feet", "20", "meters", "feet", null, null)]
    [InlineData("Convert 2^3 meters to feet", "3", "meters", "feet", null, null)]
    [InlineData("Convert 2 * 3 meters to feet", "3", "meters", "feet", null, null)]
    [InlineData("Convert 2 plus 3 meters to feet", "3", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters divided by 2 to feet", "20", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters plus 2 to feet", "20", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters to feet divided by 2", "20", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters to feet multiplied by 2", "20", "meters", "feet", null, null)]
    [InlineData("Convert double 20 meters to feet", "20", "meters", "feet", null, null)]
    [InlineData("Convert half of 20 meters to feet", "20", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters to feet, then halve it", "20", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters to feet squared", "20", "meters", "feet", null, null)]
    [InlineData("I need feet for 20 meters divided by 2", "20", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters to feet please!", "20", "meters", "feet", null, "65.62")]
    [InlineData("Could you convert 20 meters to feet for me?", "20", "meters", "feet", null, "65.62")]
    [InlineData("Convert 20 meters to feet, rounded to 2 decimal places please!", "20", "meters", "feet", null, "65.62")]
    [InlineData("Convert 20 meters to feet divided by 2, rounded to 2 decimals", "20", "meters", "feet", null, null)]
    [InlineData("Convert 20 meters to feet, rounded to 2 decimals", "20", "meters", "feet", null, "65.62")]
    [InlineData("Rounded to 2 decimals, convert 20 meters to feet", "20", "meters", "feet", null, "65.62")]
    [InlineData("I need pounds for 48 ounces", "48 ounces", "ounces", "pounds", null, "3")]
    [InlineData("I need kilograms for 32 ounces", "32", "ounces", "kilograms", null, "0.9072")]
    [InlineData("I need pounds and 48 ounces", "48", "ounces", "pounds", null, null)]
    [InlineData("I need pounds for 48 ounces", "48", "pounds", "ounces", null, null)]
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
    [InlineData("What’s a pound worth in ounces?", "1", "pound", "ounce", null, "16")]
    [InlineData("Express Theo's 6 metres in feet please", "6", "metres", "feet", null, "19.69")]
    [InlineData("Express Theo’s 6 s in minutes please", "6", "s", "minutes", null, "0.1")]
    [InlineData("What's 2 t in kilograms please", "2", "t", "kilograms", null, "2000")]
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
    [InlineData("Work out the product of twelve and four", "multiply", "twelve", "four", "48")]
    [InlineData("Multiply negative three by seven", "multiply", "negative three", "seven", "-21")]
    [InlineData("Multiply negative three by seven", "multiply", "-3", "7", "-21")]
    [InlineData("Multiply -3 by 7", "multiply", "negative three", "seven", "-21")]
    [InlineData("Multiply negative-three by seven", "multiply", "-3", "7", "-21")]
    [InlineData("Multiply minus three by seven", "multiply", "-3", "7", "-21")]
    [InlineData("Multiply positive three by seven", "multiply", "+3", "7", "21")]
    [InlineData("Multiply negative three by seven", "multiply", "three", "seven", null)]
    [InlineData("Multiply negative three by seven", "multiply", "3", "7", null)]
    [InlineData("Multiply three by seven", "multiply", "-3", "7", null)]
    [InlineData("Multiply negative three by seven", "multiply", "-3", "-7", null)]
    [InlineData("Multiply 0.3 by seven", "multiply", "3", "7", null)]
    [InlineData("Multiply 1,003 by seven", "multiply", "3", "7", null)]
    [InlineData("Multiply one hundred three by seven", "multiply", "3", "7", null)]
    [InlineData("Multiply twenty-three by seven", "multiply", "3", "7", null)]
    [InlineData("Multiply twenty-three by seven", "multiply", "23", "7", "161")]
    [InlineData("Multiply three by seven", "multiply", "3", "3", null)]
    [InlineData("Multiply three by three", "multiply", "3", "3", "9")]
    [InlineData("Multiply negative three by seven", "multiply", "-3", "8", null)]
    [InlineData("Multiply negative three by seven", "multiply", "-3 + 0", "7", null)]
    [InlineData("Work out the product of twelve and four", "multiply", "twelve", "twelve", null)]
    [InlineData("What remains after taking 12.5 percent off 80?", "percentOff", "12.5%", "80", "70")]
    [InlineData("What is fifteen percent of sixty?", "percentOf", "fifteen percent", "sixty", "9")]
    [InlineData("What's 15 percent off 200?", "percentOff", "15", "200", "170")]
    [InlineData("Find 15 percent of 60", "percentOf", "15%", "60%", null)]
    [InlineData("Find 15 percent of 60", "percentOf", "15%%", "60", null)]
    [InlineData("Find 15 percent of 60", "percentOf", "15 percent percent", "60", null)]
    [InlineData("Find 15 percent of 60", "percentOf", "15+0%", "60", null)]
    [InlineData("Find 15 percent of 60", "percentOf", "60%", "15", null)]
    [InlineData("Take 15 percent off 60", "percentOf", "15%", "60", null)]
    [InlineData("Take negative fifteen percent off sixty", "percentOff", "fifteen percent", "sixty", null)]
    [InlineData("Take negative fifteen percent off sixty", "percentOff", "negative fifteen percent", "sixty", "69")]
    [InlineData("Multiply 15 by 60", "multiply", "15%", "60", null)]
    [InlineData("What remains after taking 12.5 percent off 80?", "percentOff", "12.5", "80", "70")]
    [InlineData("What remains after taking 12.5 percent off 80?", "percentOf", "12.5", "80", null)]
    [InlineData("What remains after taking 12.5 percent off 80?", "subtract", "12.5", "80", null)]
    [InlineData("What remains after taking 12.5 percent off 80?", "subtract", "80", "12.5", null)]
    [InlineData("What remains after taking 12.5 percent off 80?", "percentOff", "80", "12.5", null)]
    [InlineData("Find fifteen percent of sixty", "percentOf", "fifteen", "sixty", "9")]
    [InlineData("Find fifteen percent of sixty", "percentOf", "sixty", "fifteen", null)]
    [InlineData("Take negative fifteen percent off sixty", "percentOff", "negative fifteen", "sixty", "69")]
    [InlineData("Take negative fifteen percent off sixty", "percentOff", "fifteen", "sixty", null)]
    [InlineData("Find 15 percent of 60", "percentOf", "15", "15", null)]
    [InlineData("Find 15 percent of 15", "percentOf", "15", "15", "2.25")]
    public void BoundedOperationsNormalizeOnlyWholeGroundedOperandQuotes(string text, string operation, string left, string right,
        string? expected) {
        var lookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of(text));
        var input = new PaletteInterpretation(PaletteInterpretationKind.Calculation, null, null, null, null, null,
            PaletteCalculationOperation.Named(operation), left, right);
        var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered, input);
        Assert.Equal(expected, GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text)?.Value);
    }

    [Theory]
    [InlineData("75 grams of spice to US teaspoons; the label says 3 grams per US teaspoon", "75 grams", "grams", "US teaspoons", "3 grams per US teaspoon", "25")]
    [InlineData("50 grams of flour to US tsp; package says 2.5 grams per US tsp", "50", "grams", "US tsp", "2.5 grams per US tsp", "20")]
    [InlineData("50 grams of flour to US tsp; package says 2.5 grams per US tsp", "50", "grams", "US tsp", "5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; package says -2.5 grams per US tsp", "50", "grams", "US tsp", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; package says 0 grams per US tsp", "50", "grams", "US tsp", "0 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; package says 2.5 grams per US tsp", "2.5", "grams", "US tsp", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; package says 2.5 grams per US tsp", "50", "US tsp", "grams", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; package says 2.5 grams per US tsp", "50", "grams", "US tsp", "grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; package says 2.5 grams per metric tsp", "50", "grams", "US tsp", "2.5 grams per metric tsp", null)]
    [InlineData("20 US tsp of flour to grams; package says 2.5 grams per US tsp", "20", "US tsp", "grams", "2.5 grams per US tsp", "50")]
    public void SuppliedDensityMustBeAnExactPositiveDirectedLabelRatio(string text, string amount, string from, string to,
        string density, string? expected) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            EnablePrivateAnswers(device);
            var question = Asking(window, text);
            var before = device.Query(question);
            var lookup = Assert.IsType<PaletteGenerativeLookup>(before.GenerativeLookup);
            var input = new PaletteInterpretation(PaletteInterpretationKind.Conversion, null, amount, from, to, null,
                DensityQuote: density);
            var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered, input);
            var after = device.Query(question with { Generative = result });
            Assert.Equal(before.Groups[0].Rows[0], after.Groups[0].Rows[0]);
            Assert.True(after.KeepsQueryPrivate);
            Assert.Null(after.SuggestionAddress);
            var card = after.Groups.SelectMany(group => group.Rows).Select(row => row.Card).FirstOrDefault(card => card?.Value is not null);
            Assert.Equal(expected, card?.Value);
            if (expected is not null) Assert.Contains(density, card!.Subtitle);
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
    [InlineData("50 grams of flour to US tsp; the old label says 2.5 grams per US tsp; corrected label says 5 grams per US tsp", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; the sugar label says 2.5 grams per US tsp", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; the label says 2.5 grams per US tsp for sugar", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; the label says 2.5 grams per teaspoon (5 ml)", "2.5 grams per teaspoon", null)]
    [InlineData("50 grams of flour to US tsp; old label says 2.5 grams per US tsp; corrected label says 5 grams per US tsp", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; label says 2.5 grams per teaspoon (5 ml)", "2.5 grams per teaspoon", null)]
    [InlineData("50 grams of flour to US tsp; sugar label says 2.5 grams per US tsp", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; package says 2.5 grams per US tsp", "2.5 grams per US tsp", "20")]
    [InlineData("50 grams of flour to US tsp; label says 2.5 grams per US tsp; 5 grams per US tsp", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; label says 2.5 grams per US tsp for sugar", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; label says 2.5 grams per US tsp (sifted)", "2.5 grams per US tsp", null)]
    [InlineData("50 grams of flour to US tsp; label says 2.5 grams per US tsp", "2.5 grams per US tsp", "20")]
    [InlineData("50 grams of flour to US tsp; 2.5 grams per US tsp", "2.5 grams per US tsp", "20")]
    [InlineData("50 grams of flour to US tsp; density: 2.5 grams per US tsp", "2.5 grams per US tsp", "20")]
    public void SuppliedDensityOwnsTheCompleteRequestAndApplicableLabel(string text, string density, string? expected) {
        var lookup = new PaletteGenerativeLookup(text);
        var input = new PaletteInterpretation(PaletteInterpretationKind.Conversion, null, "50", "grams", "US tsp", "flour",
            DensityQuote: density);
        var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered, input);
        var card = Assert.IsType<PaletteCard>(GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text));
        Assert.Equal(expected, card.Value);
        Assert.Equal(expected is null ? PaletteCardKind.Clarification : PaletteCardKind.Conversion, card.Kind);
        if (expected is not null) Assert.Contains(density, card.Subtitle);
    }

    [Theory]
    [InlineData("Celsius to Fahrenheit please")]
    [InlineData("c to f")]
    public void MissingTemperatureAmountClarifiesWithoutReplacingCuratedHelpReturn(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            var question = Asking(window, text);
            var before = device.Query(question);
            EnablePrivateAnswers(device);
            var after = device.Query(question);
            Assert.Equal(before.Groups[0].Rows[0], after.Groups[0].Rows[0]);
            Assert.True(after.KeepsQueryPrivate);
            Assert.Null(after.SuggestionAddress);
            Assert.Null(after.WebLookup);
            var card = CardOf(after);
            Assert.Equal(PaletteCardKind.Clarification, card.Kind);
            Assert.False(card.Kind.CopiesValue);
            Assert.Null(card.Value);
            Assert.Null(UnitConversion.Of(text));
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

    [Theory]
    [InlineData("Please change nine yards to feet", PaletteGenerativeRoute.Conversion)]
    [InlineData("ask ode Celsius to Fahrenheit", PaletteGenerativeRoute.Conversion)]
    [InlineData("ask ode m to t", PaletteGenerativeRoute.Conversion)]
    [InlineData("ask ode 14 * 23", PaletteGenerativeRoute.Calculation)]
    [InlineData("Find the product of eleven and seven", PaletteGenerativeRoute.Calculation)]
    [InlineData("ask ode explain 1e-3", PaletteGenerativeRoute.Calculation)]
    [InlineData("What remains after taking 12.5 percent off 80?", PaletteGenerativeRoute.Calculation, "percentOff")]
    [InlineData("Find fifteen percent of sixty", PaletteGenerativeRoute.Calculation, "percentOf")]
    [InlineData("Take -15% off 60 please", PaletteGenerativeRoute.Calculation, "percentOff")]
    [InlineData("Take 15 percent off 60 and 5 percent off 20", PaletteGenerativeRoute.Calculation)]
    [InlineData("rewrite: take fifteen percent off sixty", PaletteGenerativeRoute.Nonnumeric)]
    [InlineData("ask ode rephrase: find 15 percent of 60", PaletteGenerativeRoute.Nonnumeric)]
    [InlineData("What is a plant", PaletteGenerativeRoute.Nonnumeric)]
    [InlineData("How do I walk in nature", PaletteGenerativeRoute.Nonnumeric)]
    [InlineData("ordinary search prose", PaletteGenerativeRoute.Nonnumeric)]
    [InlineData("rewrite: convert nine yards to feet", PaletteGenerativeRoute.Nonnumeric)]
    [InlineData("ask ode summarize: multiply 14 by 23", PaletteGenerativeRoute.Nonnumeric)]
    public void CoreSelectsOneGenerationShapeWithRewritePrecedence(string text, PaletteGenerativeRoute route,
        string? percentageOperation = null) {
        var lookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of(text));
        Assert.Equal(route, lookup.Route);
        Assert.Equal(percentageOperation, lookup.PercentageOperation?.Name);
        var prose = new PaletteGenerativeResult(lookup, "Only rewritten or general text", PaletteGenerativeStatus.Answered);
        var value = GenerativeAnswerLookup.Card(lookup, prose, PalettePreferences.Default, text)?.Value;
        Assert.Equal(route == PaletteGenerativeRoute.Nonnumeric && GenerativeAnswerLookup.IsRequest(text) ? prose.Text : null, value);
    }

    [Theory]
    [InlineData("rewrite: multiply 14 by 23", "14*23")]
    [InlineData("ask ode rephrase: subtract 8 from 20", "20-8")]
    [InlineData("rewrite: take fifteen percent off sixty", "15% off 60")]
    public void NumericRewriteCannotBecomeAnExecutableInterpretation(string text, string expression) {
        var lookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of(text));
        var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered,
            new(PaletteInterpretationKind.Calculation, expression, null, null, null, null));
        Assert.Null(GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text));
    }

    [Theory]
    [InlineData("Express 9 yards as feet please", "9", "yards", "feet", "invented material", "invented density", "conversion", "27")]
    [InlineData("Express 2 cups as ml please", "2", "cups", "ml", "water", null, "conversion", "473.2")]
    [InlineData("Express 1 Imperial pint as ml please", "1", "pint", "ml", "water", null, "clarification", null)]
    [InlineData("Express 20 grams of cocoa as tsp please", "20", "grams", "tsp", "water", null, null, null)]
    [InlineData("Express 20 grams of cocoa as tsp please", "20", "grams", "tsp", "cocoa", null, "clarification", null)]
    [InlineData("Express 20 grams of cocoa as tsp please", "20", "grams", "tsp", null, null, "clarification", null)]
    [InlineData("Express 20 grams of cocoa as tsp please", "20", "grams", "tsp", null, "2 grams per tsp", "clarification", null)]
    public void OnlyMaterialAndDensityUsedByConversionMustBeGrounded(string text, string amount, string from, string to,
        string? material, string? density, string? kind, string? value) {
        var lookup = Assert.IsType<PaletteGenerativeLookup>(GenerativeAnswerLookup.Of(text));
        var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered,
            new(PaletteInterpretationKind.Conversion, null, amount, from, to, material, DensityQuote: density));
        var card = GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text);
        Assert.Equal(kind, card?.Kind.Name);
        Assert.Equal(value, card?.Value);
    }

    [Theory]
    [InlineData("Could you turn 18 grams of cocoa into teaspoons for me?", "18 grams", "grams", "teaspoons", "cocoa", "grams per US tsp.")]
    [InlineData("How much is 8 oz in cups?", "8 oz", "oz", "cups", "unknown", "unknown")]
    [InlineData("50 grams of flour to US teaspoons", "50 grams", "grams", "US teaspoons", "flour", "grams per US tsp.")]
    [InlineData("Tell me how many teaspoons 25 grams of water would fill", "25 grams", "grams", "teaspoons", "water", "1 gram per US tsp.")]
    [InlineData("50 grams of chicken to teaspoons", "50 grams", "grams", "teaspoons", "chicken", "grams per US tsp.")]
    [InlineData("50 grams of flour to US teaspoons", "50 grams", "grams", "US teaspoons", "invented material", "invented density")]
    public void UngroundedDensityStillClarifiesWithoutUsingInventedMaterial(string text, string amount, string from, string to,
        string material, string density) {
        var lookup = new PaletteGenerativeLookup(text);
        var result = new PaletteGenerativeResult(lookup, null, PaletteGenerativeStatus.Answered,
            new(PaletteInterpretationKind.Conversion, null, amount, from, to, material, DensityQuote: density));
        var card = Assert.IsType<PaletteCard>(GenerativeAnswerLookup.Card(lookup, result, PalettePreferences.Default, text));
        Assert.Equal(PaletteCardKind.Clarification, card.Kind);
        Assert.False(card.Kind.CopiesValue);
        Assert.Null(card.Value);
        if (!text.Contains(material, StringComparison.Ordinal)) {
            Assert.DoesNotContain(material, card.Title);
            Assert.Equal(UnitConversion.Resolve(text, amount, from, to, null), card);
        }
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
