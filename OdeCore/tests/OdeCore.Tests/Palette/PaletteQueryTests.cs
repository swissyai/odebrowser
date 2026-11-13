using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// Canonical spellings of the same text match alike, case and accents are
/// ignored, and the original text used to display and open a result is kept.
public sealed class PaletteQueryTests {
    #region Actions - Matching

    [Theory]
    [InlineData("cafe\u0301", "CAFÉ")]
    [InlineData("café", "CAFE\u0301")]
    [InlineData("\u1100\u1161", "가")]
    [InlineData("a\u0301\u0323", "a\u0323\u0301")]
    public void CanonicalSpellingsMatchTitlesDetailsAndPrefixes(string typed, string title) {
        var query = new PaletteQuery(typed);
        var exact = new PaletteQuery(title);

        Assert.Equal(exact.Score(title), query.Score(title));
        Assert.NotNull(query.Score(title));
        Assert.Equal(exact.Score("Notes", title), query.Score("Notes", title));
        Assert.NotNull(query.Score("Notes", title));
        Assert.True(query.Prefixes(title + " notes"));
        Assert.Equal(typed, query.Text);
    }

    [Theory]
    [InlineData("éa", "e\u0301clair Atelier")]
    [InlineData("e\u0301a", "Éclair Atelier")]
    public void CanonicalSpellingsMatchInitialsAndSubsequences(string typed, string title) {
        var query = new PaletteQuery(typed);

        Assert.Equal(250, query.Initials(title));
        Assert.Equal(250, query.Abbreviates(title));
        Assert.Equal(150, query.Abbreviates("An " + title));
    }

    [Theory]
    [InlineData("cafe", "Café Society")]
    [InlineData("café", "Cafe Society")]
    [InlineData("resume", "Résumé tips")]
    [InlineData("strasse", "Straße guide")]
    [InlineData("stras", "Straße guide")]
    [InlineData("istanbul", "İstanbul")]
    [InlineData("odon", "Ödön von Horváth")]
    [InlineData("q", "q\u0301 marks")]
    public void TypingWithoutAccentsMatchesTitlesDetailsAndPrefixes(string typed, string title) {
        var query = new PaletteQuery(typed);

        Assert.NotNull(query.Score(title));
        Assert.NotNull(query.Score("Notes", title));
        Assert.True(query.Prefixes(title));
    }

    [Fact]
    public void AnAccentedInitialStartsItsWord() =>
        Assert.Equal(250, new PaletteQuery("ea").Initials("Éclair Atelier"));

    [Theory]
    [InlineData("fi", "ﬁ")]
    [InlineData("A", "Ａ")]
    public void CompatibilityFormsStayDistinct(string typed, string title) {
        var query = new PaletteQuery(typed);

        Assert.Null(query.Score(title));
        Assert.False(query.Prefixes(title));
        Assert.Null(query.Abbreviates(title));
    }

    [Theory]
    [InlineData(0xD800)]
    [InlineData(0xDC00)]
    [InlineData(0xFFFE)]
    [InlineData(0xD800, 0xFFFE)]
    public void RejectedUnicodeDoesNotPreventFindingTheRemainingTitle(params int[] codeUnits) {
        string invalid = new([.. codeUnits.Select(value => (char)value)]);
        var query = new PaletteQuery("café");

        Assert.NotNull(query.Score(invalid + " cafe\u0301"));
        Assert.NotNull(query.Score("Notes", invalid + " cafe\u0301"));
        Assert.True(query.Prefixes("cafe\u0301" + invalid));
        Assert.Equal(250, new PaletteQuery("éa").Initials(invalid + " e\u0301clair Atelier"));
        Assert.Equal(150, new PaletteQuery("éx").Abbreviates(invalid + " e\u0301clair extra"));

        var malformed = new PaletteQuery(invalid + " cafe\u0301");
        Assert.NotNull(malformed.Score(invalid + " café"));
        Assert.True(malformed.Prefixes(invalid + " café notes"));
        Assert.Equal(invalid + " cafe\u0301", malformed.Text);
    }

    #endregion
}
