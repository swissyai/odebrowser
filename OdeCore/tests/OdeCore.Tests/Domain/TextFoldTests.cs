using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// The core folds text it compares without case or diacritics one way, for
/// search suggestions, encyclopedia titles, written answers and search engine
/// names alike, whatever form the text arrives in.
public sealed class TextFoldTests {
    #region Actions - Folding

    [Theory]
    [InlineData("Caf\u00E9", "cafe")]
    [InlineData("CAF\u00C9", "cafe")]
    [InlineData("Cafe\u0301", "cafe")]
    [InlineData("\u00D6d\u00F6n_von  Horv\u00E1th", "odon_von  horvath")]
    [InlineData("  Stra\u00DFe  ", "  stra\u00DFe  ")]
    [InlineData("\u0130stanbul", "istanbul")]
    [InlineData("\u039B\u039F\u0393\u039F\u03A3", "\u03BB\u03BF\u03B3\u03BF\u03C3")]
    [InlineData("\u03A3\u03BF\u03C6\u03AF\u03B1\u03C2", "\u03C3\u03BF\u03C6\u03B9\u03B1\u03C2")]
    [InlineData("na\u00EFve r\u00E9sum\u00E9", "naive resume")]
    [InlineData("don\u2019t It's \u2018q\u2019", "don\u2019t it's \u2018q\u2019")]
    [InlineData("\uD55C\uAD6D\uC5B4", "\uD55C\uAD6D\uC5B4")]
    [InlineData("\u1112\u1161\u11AB\u1100\u116E\u11A8", "\uD55C\uAD6D")]
    [InlineData("\uFB01le", "\uFB01le")]
    [InlineData("\u212Bngstr\u00F6m", "angstrom")]
    [InlineData("\u1E9E", "\u00DF")]
    [InlineData("\u0110\u00E0 N\u1EB5ng", "\u0111a nang")]
    [InlineData("\u00D8resund \u00C6sir", "\u00F8resund \u00E6sir")]
    [InlineData("", "")]
    [InlineData("\u0995\u09C7\u09BE", "\u0995\u09CB")]
    [InlineData("A\u030A\u0323", "a")]
    [InlineData("\u01C5", "\u01C6")]
    [InlineData("\u212A", "k")]
    [InlineData("\u03A9\u0301", "\u03C9")]
    public void FoldingDropsCaseAndDiacriticsAndKeepsEverythingElse(string text, string folded) =>
        Assert.Equal(folded, TextFold.Folded(text));

    [Fact]
    public void TextNormalizationRejectsIsComparedAsAReplacementCharacter() {
        Assert.Equal("x\uFFFDy", TextFold.Folded("x\uFFFEy"));
        Assert.Equal("x\uFFFDy", TextFold.Normalized("x\uFFFEy"));
        Assert.Equal("a\uFFFDb", TextFold.Normalized("a\uD800b"));
        Assert.Equal("\u00E9", TextFold.Normalized("e\u0301"));
    }

    [Fact]
    public void WrittenAnswersFoldLikeEverythingElseWithoutApostrophes() {
        Assert.Equal(["dont", "its", "q"], AnswerText.Of("Don\u2019t It's \u2018Q\u2019").Words);
        Assert.Equal(AnswerText.Of("istanbul tabs").Words, AnswerText.Of("\u0130stanbul TABS").Words);
        Assert.Equal(AnswerText.Of("pin tab").Phrase, AnswerText.Of("P\u00EDn T\u00E4b").Phrase);
    }

    #endregion
}
