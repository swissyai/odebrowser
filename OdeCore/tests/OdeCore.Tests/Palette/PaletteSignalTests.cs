using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// How a page's use becomes points: a visit to a kept page counts twice a
/// link visit, usage grows sixty points per doubling of frecency to a cap of
/// three hundred and a site's front page adds up to a hundred for the whole
/// site, whose frecency sums every page the memory or the history knows.
public sealed class PaletteSignalTests {
    #region Static Variables

    private static readonly DateTimeOffset Day = new(2026, 11, 8, 12, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Frecency

    [Fact]
    public void AVisitToAKeptPageCountsTwiceALinkVisit() {
        const string page = "https://example.org/a";

        Assert.Equal(1, PaletteMemory.Starting(Day).Visited(page, null, Day).Frecency(page, null, Day), 6);
        Assert.Equal(2, PaletteMemory.Starting(Day).Visited(page, null, Day, kept: true).Frecency(page, null, Day), 6);
    }

    [Fact]
    public void AHostsFrecencySumsItsPagesFromTheMemoryAndThenTheHistory() {
        var memory = PaletteMemory.Starting(Day.AddYears(-1))
            .Visited("https://www.example.org/a", null, Day).Visited("https://example.org:8443/b", null, Day)
            .Visited("https://other.example/", null, Day);
        var space = StoredSessionCodec.DecodeSpace(new JsonObject {
            ["id"] = new JsonObject { ["rawValue"] = Guid.NewGuid().ToString("D") },
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString("D") },
            ["name"] = "Reading",
            ["history"] = new JsonArray(
                History("https://example.org/a", 5, Day), History("https://example.org/c", 3, Day), History("https://example.org/d", 1, Day.AddDays(-30)))
        });
        var context = new PaletteContext(space, null, isPrivate: false, allowsInternalPages: true, PalettePreferences.Default,
            SearchCatalog.Starting(language: null, region: null), memory, [], Day);

        Assert.Equal(2, memory.HostFrecencies(Day)["example.org"], 6);
        // The remembered page keeps its memory; the two the memory never saw add their history, one halved by a month.
        Assert.Equal(2 + 3 + 0.5, context.HostFrecency("example.org"), 6);
        Assert.Equal(0, context.HostFrecency("unknown.example"), 6);
    }

    #endregion

    #region Actions - Points

    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 60)]
    [InlineData(3, 120)]
    [InlineData(31, 300)]
    [InlineData(1_000, 300)]
    public void UsageGrowsSixtyPerDoublingToACap(double frecency, int points) =>
        Assert.Equal(points, PaletteSignal.Usage.Points(Evidence(frecency, 0, "https://example.org/page"), Context()));

    [Theory]
    [InlineData(1, 30)]
    [InlineData(3, 60)]
    [InlineData(9.1, 100)]
    [InlineData(500, 100)]
    public void ASitesFrontPageAddsThirtyPerDoublingOfTheSiteToACap(double hostFrecency, int points) {
        Assert.Equal(points, PaletteSignal.Usage.Points(Evidence(0, hostFrecency, "https://example.org/"), Context()));
        Assert.Equal(0, PaletteSignal.Usage.Points(Evidence(0, hostFrecency, "https://example.org/page"), Context()));
        Assert.Equal(0, PaletteSignal.Usage.Points(Evidence(0, hostFrecency, "https://example.org/?q=1"), Context()));
    }

    [Fact]
    public void AFrontPageLeadsOnItsSiteWhenItsOwnVisitsFallShort() {
        var context = Context();

        Assert.False(PaletteSignal.Usage.Leads(Evidence(2, 0, "https://example.org/page"), context));
        Assert.True(PaletteSignal.Usage.Leads(Evidence(2, 2, "https://example.org/"), context));
    }

    private static PaletteEvidence Evidence(double frecency, double hostFrecency, string url) =>
        new(Match: 0, LeadsByText: false, PrefixesTitle: false, frecency, LastUsed: null, IsOpen: false, IsKept: false, Learned: 0,
            PlaceText.Of("Page", url), Offset: 0, hostFrecency, Typed: false, TypedUses: 0, Visits: 0);

    private static PaletteContext Context() => new(null, null, isPrivate: false, allowsInternalPages: true, PalettePreferences.Default,
        SearchCatalog.Starting(language: null, region: null), PaletteMemory.Starting(Day), [], Day);

    private static JsonNode History(string url, int visits, DateTimeOffset last) => new JsonObject {
        ["id"] = Guid.NewGuid().ToString("D"),
        ["url"] = url,
        ["title"] = "Page",
        ["firstVisitedAt"] = StoredSessionCodec.Seconds(last.AddDays(-1)),
        ["lastVisitedAt"] = StoredSessionCodec.Seconds(last),
        ["visitCount"] = visits
    };

    #endregion
}
