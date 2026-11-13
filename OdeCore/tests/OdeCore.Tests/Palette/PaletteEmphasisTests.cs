using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// What of a row's title the palette marks for what was typed, as UTF-16
/// runs of the title as the row holds it: a tab's or page's title marks
/// every place a typed word appears, matched as the palette matches words,
/// ignoring case and accents; a search suggestion
/// marks what follows the typed text, compared without case or diacritics,
/// or else each of its words the typed text lacks.
public sealed class PaletteEmphasisTests {
    #region Actions - Matches

    [Theory]
    [InlineData("Swift Evolution", "evo", 6, 3)]
    [InlineData("Swift Evolution", "swift evo", 0, 5, 6, 3)]
    [InlineData("Swift Evolution", "  evo  ", 6, 3)]
    [InlineData("Swift Evolution", "x")]
    [InlineData("Caf\u00E9 Society", "caf\u00E9", 0, 4)]
    [InlineData("Caf\u00E9 Society", "cafe", 0, 4)]
    [InlineData("R\u00E9sum\u00E9 tips", "resume", 0, 6)]
    [InlineData("Stra\u00DFe guide", "strasse", 0, 6)]
    [InlineData("Stra\u00DFe guide", "stras", 0, 5)]
    [InlineData("Decomposed Cafe\u0301", "caf\u00E9", 11, 5)]
    [InlineData("\u039B\u039F\u0393\u039F\u03A3 news", "\u03BB\u03BF\u03B3\u03BF\u03C2", 0, 5)]
    [InlineData("\u0130stanbul", "istanbul", 0, 8)]
    [InlineData("banana bandana", "ana", 1, 3, 11, 3)]
    [InlineData("TEST test Test", "test", 0, 4, 5, 4, 10, 4)]
    [InlineData("aaa", "aa", 0, 2)]
    [InlineData("Ode Browser", "od br", 0, 2, 4, 2)]
    [InlineData("Ode Browser", "ode od", 0, 3)]
    [InlineData("Docs \u2014 GitHub", "git", 7, 3)]
    [InlineData("Emoji \U0001F600 party", "party", 9, 5)]
    [InlineData("\uFFFE cafe\u0301 garden", "garden", 8, 6)]
    public void ATabTitleMarksEveryPlaceATypedWordMatches(string title, string typed, params int[] runs) =>
        Assert.Equal(Runs(runs), Marked(PaletteRowKind.Tab, title, typed));

    #endregion

    #region Actions - Completion

    [Theory]
    [InlineData("what is the odyssey about", "what is the", 11, 14)]
    [InlineData("odyssey summary", "Odyssey", 7, 8)]
    [InlineData("weather tomorrow", "weather", 7, 9)]
    [InlineData("caf\u00E9s near me", "cafe", 4, 9)]
    [InlineData("Cafe\u0301 menu", "caf\u00E9", 5, 5)]
    [InlineData("\u00D6d\u00F6n von Horv\u00E1th", "odon", 4, 12)]
    [InlineData("Swift 5.9 release notes", "swift 5", 7, 16)]
    [InlineData("Emoji \U0001F600 party ideas", "emoji \U0001F600 party", 14, 6)]
    [InlineData("abc", "abc")]
    [InlineData("tokyo time", "Tokyo Time")]
    [InlineData("caf\u00E9 paris", "cafe paris")]
    [InlineData("best odyssey translation", "odyssey best", 13, 11)]
    [InlineData("what is love", "what  is", 8, 4)]
    [InlineData("don't stop me now", "dont", 0, 5, 6, 4, 11, 2, 14, 3)]
    [InlineData("odd", "odyssey", 0, 3)]
    [InlineData("e.g. examples", "eg", 0, 3, 5, 8)]
    [InlineData("1,000 km in miles", "km miles", 0, 5, 9, 2)]
    public void ASuggestionMarksWhatItAddsToTheTypedText(string title, string typed, params int[] runs) =>
        Assert.Equal(Runs(runs), Marked(PaletteRowKind.SearchSuggestion, title, typed));

    #endregion

    #region Actions - Kinds

    [Fact]
    public void OnlyTabsFoldersPagesAndSuggestionsMarkTheirTitlesAndOnlyOnceSomethingIsTyped() {
        var query = new PaletteQuery("swift");
        foreach (var kind in PaletteRowKind.All) {
            var marked = TitleEmphasis.Of(PaletteRow.Of(kind, "Swift", ""), query);
            bool marks = kind == PaletteRowKind.SearchSuggestion || kind == PaletteRowKind.Tab || kind == PaletteRowKind.PinnedTab
                || kind == PaletteRowKind.SavedTab || kind == PaletteRowKind.Folder || kind == PaletteRowKind.History
                || kind == PaletteRowKind.ArchivedTab;
            Assert.Equal(marks, marked is not null);
        }
        Assert.Null(TitleEmphasis.Of(PaletteRow.Of(PaletteRowKind.Tab, "Swift", ""), new PaletteQuery("   ")));
        Assert.Equal(new PaletteEmphasis([]), TitleEmphasis.Of(PaletteRow.Of(PaletteRowKind.Tab, "Swift", ""), new PaletteQuery("x")));
    }

    #endregion

    #region Actions - Fixtures

    private static PaletteEmphasis? Marked(PaletteRowKind kind, string title, string typed) =>
        TitleEmphasis.Of(PaletteRow.Of(kind, title, ""), new PaletteQuery(typed));

    private static PaletteEmphasis Runs(int[] pairs) =>
        new([.. pairs.Chunk(2).Select(pair => new TextRun(pair[0], pair[1]))]);

    #endregion
}

/// The palette marks its rows' titles for the text it answered, so a row and
/// its marks always agree.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void APaletteAnswerMarksTheTitlesOfTabsAndSuggestionsForTheTextItAnswered() {
        var (target, shown) = (Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(target, "Swift Evolution", "https://www.swift.org/swift-evolution/"),
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")]);
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));

        var answer = device.Query(Asking(window, "swift evo") with { Remote = ["swift evolution proposals"] });
        var rows = answer.Groups.SelectMany(group => group.Rows).ToList();

        Assert.Equal(new PaletteEmphasis([new(0, 5), new(6, 3)]), rows.Single(row => row.TabId == target).Emphasis);
        Assert.Equal(new PaletteEmphasis([new(9, 16)]), rows.Single(row => row.Kind == PaletteRowKind.SearchSuggestion).Emphasis);
        Assert.Null(rows.Single(row => row.Kind == PaletteRowKind.Search).Emphasis);
        Assert.All(device.Query(Asking(window, "")).Groups.SelectMany(group => group.Rows), row => Assert.Null(row.Emphasis));
        var scoped = device.Query(Asking(window, "evo") with { Scope = PaletteScope.Tabs });
        Assert.Equal(new PaletteEmphasis([new(6, 3)]), Assert.Single(Assert.Single(scoped.Groups).Rows).Emphasis);
    }
}
