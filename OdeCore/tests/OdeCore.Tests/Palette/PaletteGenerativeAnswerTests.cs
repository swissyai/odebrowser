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
    [InlineData("why")]
    [InlineData("why is")]
    [InlineData("why is the")]
    [InlineData("weather tomorrow")]
    [InlineData("French restaurants")]
    [InlineData("https://example.test/why is the sky blue")]
    [InlineData("ask ode explain example.com")]
    [InlineData("ask ode explain localhost:3000/test")]
    [InlineData("ask ode rewrite jane@example.test")]
    [InlineData("ask ode explain my password hunter2")]
    [InlineData("ask ode hi")]
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
                Assert.False(ordinary.KeepsQueryPrivate);
                Assert.Null(ordinary.GenerativeLookup);
                Assert.NotNull(ordinary.SuggestionAddress);
                Assert.NotNull(ordinary.WebLookup);
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
        foreach (var prompt in new[] { "why is the sky blue?", "ask ode explain my password hunter2", "rewrite", "rewrite hi", "rewrite:" }) {
            app.Send(new RecordPaletteChoice(window, prompt, destination));
            app.Send(new RecordPaletteChoice(window, prompt, destination));
        }
        Assert.Empty(app.Device.MemoryOf(space).Choices);
        Assert.Empty(app.Device.MemoryOf(space).Places);
        if (kind == "persistent") {
            app.Send(new RecordPaletteChoice(window, "ordinary search", destination));
            Assert.Single(app.Device.MemoryOf(space).Choices);
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
