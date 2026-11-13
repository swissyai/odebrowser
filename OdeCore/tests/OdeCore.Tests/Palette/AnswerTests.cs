using System.Text.Json;

using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;
using Xunit.Abstractions;

namespace OdeCore.Tests;

/// The written answers the palette shows: every card Ode ships reads, runs a
/// command Ode has and links a guide; real questions in people's own words
/// rank their card first at least nine times in ten, which holds for the
/// fifth of them kept back from tuning too; a question leads the palette with
/// its answer while an address or a site's name searches as before; and the
/// palette's Ode Help mode lists only answers.
public sealed class AnswerTests(ITestOutputHelper output) {
    #region Static Variables

    /// The share of golden questions whose card must rank first.
    private const double RequiredAccuracy = 0.90;

    #endregion

    [Fact]
    public void EveryShippedAnswerReadsRunsSomethingOdeHasAndLinksAGuide() {
        var catalog = AnswerCatalog.Shipped;

        Assert.True(catalog.Entries.Count >= 200, $"{catalog.Entries.Count} live answers");
        Assert.Equal(catalog.Entries.Count, catalog.Entries.Select(entry => entry.Card.Id).Distinct().Count());
        Assert.All(catalog.Entries, entry => {
            var card = entry.Card;
            Assert.InRange(card.Steps.Count, 1, 3);
            Assert.StartsWith("https://odebrowser.com/guides/", card.Guide, StringComparison.Ordinal);
            if (card.Action is { } action)
                Assert.Equal(1, new object?[] { action.Command, action.SettingsPage, action.SpacePage, action.ApplicationAction }
                    .Count(target => target is not null));
        });
        Assert.NotEmpty(catalog.Suggested);
    }

    [Fact]
    public void GoldenQuestionsRankTheirCardFirst() {
        var questions = GoldenQuestions();
        var index = AnswerCatalog.Shipped.Index;
        List<(int Number, string Text, string Expected, string? Ranked)> results = [.. questions.Select((question, number) =>
            (number, question.Text, question.Expected, index.Rank(question.Text).FirstOrDefault()?.Card.Id))];
        bool Right((int Number, string Text, string Expected, string? Ranked) result) => result.Ranked == result.Expected;
        var heldOut = results.Where(result => IsHeldOut(result.Number)).ToList();
        double accuracy = (double)results.Count(Right) / results.Count;
        double heldOutAccuracy = (double)heldOut.Count(Right) / heldOut.Count;

        output.WriteLine($"Golden questions: {results.Count(Right)} of {results.Count} first ({accuracy:P1}).");
        output.WriteLine($"Held out from tuning: {heldOut.Count(Right)} of {heldOut.Count} first ({heldOutAccuracy:P1}).");
        foreach (var result in results.Where(result => !Right(result)))
            output.WriteLine($"  \"{result.Text}\" ranked {result.Ranked ?? "nothing"} first, not {result.Expected}");
        Assert.True(accuracy >= RequiredAccuracy,
            $"Only {accuracy:P1} of the golden questions rank their card first; at least {RequiredAccuracy:P0} must.");
    }

    [Theory]
    [InlineData("how do i split view", "split-view-create")]
    [InlineData("undo close tab", "reopen-closed-tab")]
    [InlineData("where are my boosts", "edit-boost")]
    [InlineData("settings", "open-settings")]
    [InlineData("little arc", "quick-window")]
    [InlineData("easels", "arc-easels")]
    [InlineData("how do i do split view?", "split-view-create")]
    [InlineData("tabs on top", "top-tabs")]
    [InlineData("tree style tabs", "tree-tabs")]
    [InlineData("back to playing tab", "back-to-playing-tab")]
    public void AQuestionLeadsWithItsAnswer(string text, string card) =>
        Assert.Equal(card, AnswerCatalog.Shipped.Index.Lead(text)?.Id);

    [Theory]
    [InlineData("github.com")]
    [InlineData("https://example.com/split-view")]
    [InlineData("github")]
    [InlineData("weather")]
    [InlineData("news")]
    [InlineData("youtube")]
    [InlineData("gmail")]
    [InlineData("netflix")]
    [InlineData("amazon")]
    [InlineData("taylor swift")]
    [InlineData("best pizza near me")]
    [InlineData("zoom")]
    [InlineData("what is the")]
    [InlineData("how do i")]
    public void AnAddressOrASiteSearchesAsBefore(string text) =>
        Assert.Null(AnswerCatalog.Shipped.Index.Lead(text));

    /// Golden questions whose card is live, in file order.
    private static IReadOnlyList<(string Text, string Expected)> GoldenQuestions() {
        using var stream = File.OpenRead(Path.Combine(AppContext.BaseDirectory, "Palette", "Fixtures", "AnswerQuestions.json"));
        using var document = JsonDocument.Parse(stream);
        return [.. document.RootElement.GetProperty("questions").EnumerateArray()
            .Where(question => !(question.TryGetProperty("pending", out var pending) && pending.GetBoolean()))
            .Select(question => (question.GetProperty("text").GetString()!, question.GetProperty("expect").GetString()!))];
    }

    /// Every fifth golden question is kept back: ranking is tuned on the rest
    /// and reported on these separately.
    private static bool IsHeldOut(int number) => number % 5 == 4;
}
