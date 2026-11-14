using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// How typed terms score against a page by where they land: the start of the
/// title, of a host label, of a title word, of a path segment, inside a title
/// word, inside a host label, or inside the path or the query string; every
/// term must land somewhere, the row takes the average, and an exact title,
/// host or host label adds its bonus once.
public sealed class PlaceTextTests {
    #region Actions - Classes

    [Theory]
    [InlineData("chang", "Changelog | Patterns", "https://patterns.example/changelog", 1_000)]
    [InlineData("clou", "Overview", "https://dash.cloudy.example/", 900)]
    [InlineData("stak", "441m Staking Issuance - Docs", "https://docs.example/document/d/1O3B/edit", 700)]
    [InlineData("quickled", "Integrate email auth", "https://codehub.example/avery/QuickLedger/pull/73", 550)]
    [InlineData("parall", "Build a smooth scroll", "https://blog.example/tutorials/cards-parallax", 550)]
    [InlineData("emor", "Memory and context", "https://codehub.example/", 300)]
    [InlineData("wise", "User Interviews", "https://talkwise.example/", 250)]
    [InlineData("andid", "Integrate email auth", "https://codehub.example/avery/AutoCandid/pull/73", 150)]
    [InlineData("darkmode", "Ferrite Computer Company", "https://ferrite.example/?ref=darkmodedesign", 150)]
    public void EachClassScoresItsPoints(string typed, string title, string url, int points) =>
        Assert.Equal(points, new PaletteQuery(typed).Score(PlaceText.Of(title, url))?.Points);

    [Fact]
    public void ATermShorterThanThreeLettersMatchesNothingInsideATitleWord() {
        var text = PlaceText.Of("Memory and context", "https://codehub.example/");

        Assert.Null(new PaletteQuery("em").Score(text));
        Assert.Equal(300, new PaletteQuery("emo").Score(text)?.Points);
    }

    [Fact]
    public void APublicSuffixIsNoHostLabel() {
        Assert.Null(new PaletteQuery("example").Score(PlaceText.Of("Overview", "https://dash.cloudy.example/")));
        Assert.Null(new PaletteQuery("co").Score(PlaceText.Of("Overview", "https://shop.cloudy.co.uk/")));
        Assert.Equal(["shop", "cloudy"], PlaceText.Of("Overview", "https://shop.cloudy.co.uk/").HostLabels);
        Assert.Equal("cloudy", PlaceText.Of("Overview", "https://www.cloudy.example/").Name);
        Assert.Equal(["localhost"], PlaceText.Of("Local", "http://localhost:5173/").HostLabels);
        Assert.Equal(["127.0.0.1"], PlaceText.Of("Local", "http://127.0.0.1:4173/?review=1").HostLabels);
    }

    #endregion

    #region Actions - Titles

    [Theory]
    [InlineData("(9+) Governance", "Governance")]
    [InlineData("(857) Jordan Hale - Videotube", "Jordan Hale - Videotube")]
    [InlineData("(1)  Field guide", "Field guide")]
    [InlineData("441m Staking Issuance", "441m Staking Issuance")]
    [InlineData("(beta) Board", "(beta) Board")]
    [InlineData("(9+)", "(9+)")]
    [InlineData("(9+)Board", "(9+)Board")]
    [InlineData("Inbox (2,870) - Mail", "Inbox (2,870) - Mail")]
    public void ALeadingUnreadBadgeIsDroppedForMatching(string title, string read) {
        var text = PlaceText.Of(title, "https://notes.example/page");

        Assert.Equal(read, text.Title);
        Assert.Equal(read == "Governance" ? 1_000 : (int?)null, read == "Governance" ? new PaletteQuery("gov").Score(text)?.Points : null);
    }

    [Fact]
    public void TheCoreTitleFollowsTheBadgeAndStopsBeforeTheSiteName() {
        Assert.Equal("Jordan Hale", PlaceText.Of("(857) Jordan Hale - Videotube", "https://www.videotube.example/@jordanhale/videos").Core);
        Assert.Equal("Videotube", PlaceText.Of("(86) Videotube", "https://www.videotube.example/").Core);
        Assert.Equal(1_150, new PaletteQuery("jordan hale").Score(PlaceText.Of("(857) Jordan Hale - Videotube", "https://www.videotube.example/@jordanhale/videos"))?.Points);
    }

    #endregion

    #region Actions - Rows

    [Fact]
    public void EveryTermMustLandSomewhereAndTheRowTakesTheAverage() {
        var text = PlaceText.Of("Stake Watch Analytics", "https://lumen.stakewatch.example/address/acct-0001");

        Assert.Equal(850, new PaletteQuery("stake watch").Score(text)?.Points);
        Assert.Null(new PaletteQuery("stake other").Score(text));
    }

    [Fact]
    public void TheBestClassPerTermCountsNotTheFirst() {
        var text = PlaceText.Of("Myrecall notes: recall engine", "https://codehub.example/team/notes");

        Assert.Equal(700, new PaletteQuery("recall").Score(text)?.Points);
    }

    [Fact]
    public void AnExactTitleHostOrHostLabelAddsItsBonusOnce() {
        Assert.Equal(1_300, new PaletteQuery("safe").Score(PlaceText.Of("Safe", "https://multisig.lumen.example/apps/open?safe=1"))?.Points);
        Assert.Equal(1_300, new PaletteQuery("safe").Score(PlaceText.Of("Safe - Wallet", "https://multisig.lumen.example/apps/open"))?.Points);
        Assert.Equal(1_300, new PaletteQuery("strasse").Score(PlaceText.Of("Straße - Site", "https://notes.example/"))?.Points);
        Assert.Equal(1_300, new PaletteQuery("\U00010428").Score(PlaceText.Of("\U00010400 - Site", "https://notes.example/"))?.Points);
        Assert.Equal(1_200, new PaletteQuery("notely").Score(PlaceText.Of("The workspace | Notely", "https://notely.example"))?.Points);
        Assert.Equal(1_200, new PaletteQuery("localhost").Score(PlaceText.Of("Local", "http://localhost:5173/"))?.Points);
        Assert.Equal(1_000, new PaletteQuery("talk").Score(PlaceText.Of("Community Forum", "https://talk.lumen.example/"))?.Points);
        Assert.Equal(900, new PaletteQuery("talk").Score(PlaceText.Of("Wise AI | Interviews", "https://talkwise.example/"))?.Points);
    }

    [Fact]
    public void TheEarliestAddressHitNamesTheOffsetAndAHostLabelStartIsNoted() {
        var text = PlaceText.Of("Integrate email auth", "https://codehub.example/avery/QuickLedger/pull/73");

        var inPath = new PaletteQuery("quickledger").Score(text)!.Value;
        Assert.Equal(("codehub.example/avery/".Length, false), (inPath.Offset, inPath.StartsHostLabel));
        var inHost = new PaletteQuery("codehub").Score(text)!.Value;
        Assert.Equal((0, true), (inHost.Offset, inHost.StartsHostLabel));
        Assert.Equal(int.MaxValue, new PaletteQuery("email").Score(text)!.Value.Offset);
    }

    #endregion
}
