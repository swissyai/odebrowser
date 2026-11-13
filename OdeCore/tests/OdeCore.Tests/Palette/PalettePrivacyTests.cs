using System.Text.Json.Nodes;

using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// What the palette keeps to itself while a person types, even where they
/// turned search suggestions on: an address, text a local row already
/// answers, and anything that looks like a secret. Ordinary searches still
/// ask, and a provider the person entered follows the same rules.
public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("github.com/settings")]
    [InlineData("https://example.com/account?token=1")]
    [InlineData("localhost:3000")]
    [InlineData("file:///Users/someone/Documents")]
    [InlineData("about:blank")]
    public void APaletteSendsNoTypedAddressForSuggestions(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) Assert.Null(device.Query(Asking(window, text)).SuggestionAddress);
    }

    [Theory]
    [InlineData("sk-proj-4f9a2c7e1b8d3f6a0c5e9b2d7f1a4c8e")]
    [InlineData("ghp_0123456789abcdefABCDEF0123456789")]
    [InlineData("AKIAIOSFODNN7EXAMPLE")]
    [InlineData("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl")]
    [InlineData("my token is 7f3a9c2e5b8d1f4a6c0e9b3d7a2f5c8e")]
    [InlineData("P@ssw0rd123")]
    [InlineData("hunter2!x")]
    [InlineData("jane.doe@example.com")]
    [InlineData("reset password for jane.doe@example.com")]
    [InlineData("4111 1111 1111 1111")]
    [InlineData("iban 123456789012345")]
    public void APaletteSendsNothingThatLooksLikeASecretForSuggestions(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) Assert.Null(device.Query(Asking(window, text)).SuggestionAddress);
    }

    [Theory]
    [InlineData("crest browser")]
    [InlineData("c++17 features")]
    [InlineData("iphone 15 pro")]
    [InlineData("node.js tutorial")]
    [InlineData("what happened in 2026")]
    [InlineData("AT&T customer service")]
    public void APaletteStillAsksForSuggestionsForOrdinarySearches(string text) {
        var (device, window) = SuggestingPalette([]);
        using (device) Assert.NotNull(device.Query(Asking(window, text)).SuggestionAddress);
    }

    [Fact]
    public void APaletteSendsNothingWhileALocalMatchLeadsForTheText() {
        var (device, window) = SuggestingPalette([], ("https://www.amazon.de/gp/order-history", "Your Orders", 6, 400, 1));
        using (device) {
            var answer = device.Query(Asking(window, "amazon"));
            Assert.Equal(PaletteSection.TopHit, answer.Groups[0].Section);
            Assert.Null(answer.SuggestionAddress);
            Assert.Null(device.Query(Asking(window, "24 * 7")).SuggestionAddress);
            Assert.NotNull(device.Query(Asking(window, "kitchen tiles")).SuggestionAddress);
            // A written answer leading still lets a question search.
            var question = device.Query(Asking(window, "how do i split view"));
            Assert.Equal(PaletteRowKind.Answer, question.Groups[0].Rows[0].Kind);
            Assert.NotNull(question.SuggestionAddress);
        }
    }

    [Fact]
    public void AProviderThePersonEnteredGetsNoAddressOrSecretEither() {
        var (device, window) = SuggestingPalette([]);
        using (device) {
            var youtube = device.Query(Asking(window, "yt")).OfferedSearch!.Provider;
            PaletteAnswer Searching(string text) => device.Query(Asking(window, text) with { Provider = youtube });
            Assert.NotNull(Searching("lofi beats").SuggestionAddress);
            Assert.Null(Searching("youtube.com/watch?v=abc").SuggestionAddress);
            Assert.Null(Searching("ghp_0123456789abcdefABCDEF0123456789").SuggestionAddress);
        }
    }

    /// A device whose only Space suggests searches, with `tabs` open and
    /// `history` visited, and a window that shows it.
    private static (TestDevice Device, Guid Window) SuggestingPalette(JsonNode[] tabs,
        params (string Url, string Title, int Visits, double FirstDaysAgo, double LastDaysAgo)[] history) {
        var (session, space) = PaletteSession(tabs, history);
        session["spaces"]![0]!["browsingPreferences"]!["searchSuggestionsEnabled"] = true;
        var device = new TestDevice(session);
        return (device, device.Open(space));
    }
}
