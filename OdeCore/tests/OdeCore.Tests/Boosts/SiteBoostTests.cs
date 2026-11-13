using System.Text;
using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// A Space's Boosts: one for each site, kept as the Boost rules normalize
/// them, saved with the Space and read back from a saved session, and
/// carried through an export into the Space an import makes.
public sealed partial class BrowserContractsTests {
    private static SiteBoost Boost(string site, bool enabled = true, IReadOnlyList<string>? hidden = null, string css = "") =>
        new(site, enabled, IsDark: false, TintHue: 235, TintStrength: 0.4, Brightness: 1, Contrast: 1.2, BoostFont.Serif,
            hidden ?? ["#sidebar"], css);

    [Fact]
    public void ABoostNamesItsSiteByHostWithoutCaseFinalDotOrALeadingWww() {
        Assert.Equal("example.com", SiteBoost.SiteOf("WWW.Example.com."));
        Assert.Equal("news.example.com", SiteBoost.SiteOf("news.example.com"));
        // "www." stays when it is all of the domain there is.
        Assert.Equal("www.com", SiteBoost.SiteOf("www.com"));
        Assert.Equal("127.0.0.1", SiteBoost.SiteOf("127.0.0.1"));
        Assert.Null(SiteBoost.SiteOf(""));
        Assert.Null(SiteBoost.SiteOf("example.com/path"));
        Assert.Null(SiteBoost.SiteOf("exa mple.com"));
        Assert.Null(SiteBoost.SiteOf(new string('a', SiteBoost.MaximumSiteLength + 1)));
    }

    [Fact]
    public void ABoostIsKeptWithinItsRanges() {
        var kept = (Boost("Example.com", hidden: [" #a ", "#a", "", "div { color: red", "a[href", "a /* x */", "a[href=\"}\"]",
            "main > .feed:nth-of-type(2)", "md\\:flex"]) with {
            TintHue = -30,
            TintStrength = 4,
            Brightness = 9,
            Contrast = double.NaN,
            CustomCss = new string('x', SiteBoost.MaximumCustomCssLength + 10)
        }).Normalized()!;

        Assert.Equal("example.com", kept.Site);
        Assert.Equal((330d, 1d, SiteBoost.MaximumLevel, 1d), (kept.TintHue, kept.TintStrength, kept.Brightness, kept.Contrast));
        // Each hidden element once, and none that could reach the rules after its own.
        Assert.Equal(["#a", "main > .feed:nth-of-type(2)", "md\\:flex"], kept.HiddenSelectors);
        Assert.Equal(SiteBoost.MaximumCustomCssLength, kept.CustomCss.Length);
        Assert.Null(Boost("not a site").Normalized());
    }

    [Fact]
    public void ASpaceKeepsOneBoostForEachSiteUntilItIsRemoved() {
        var (session, space, _) = SavedSession();
        using var device = new TestDevice(session["session"]!);

        device.Send(new SetSiteBoost(device.Workspace, space, Boost("www.example.com")));
        device.Send(new SetSiteBoost(device.Workspace, space, Boost("news.example.org", hidden: [])));
        device.Send(new SetSiteBoost(device.Workspace, space, Boost("example.com", enabled: false, hidden: ["#ads", "#sidebar"])));

        var boosts = device.Authority.Current.Spaces.Single(kept => kept.Id == space).Settings.Boosts!;
        Assert.Equal(["example.com", "news.example.org"], boosts.Sites.Select(boost => boost.Site));
        Assert.False(boosts.For("example.com")!.IsEnabled);
        Assert.Equal(["#ads", "#sidebar"], boosts.For("example.com")!.HiddenSelectors);
        Assert.Null(boosts.For("www.example.com"));

        Assert.IsType<InvalidBoostSite>(Assert.Throws<Rejected>(() =>
            device.Send(new SetSiteBoost(device.Workspace, space, Boost("bad site"))).ToArray()).Rejection);

        device.Send(new RemoveSiteBoost(device.Workspace, space, "WWW.example.com"));
        Assert.Equal(["news.example.org"], device.Authority.Current.Spaces.Single(kept => kept.Id == space).Settings.Boosts!.Sites
            .Select(boost => boost.Site));
        device.Send(new RemoveSiteBoost(device.Workspace, space, "news.example.org"));
        Assert.Null(device.Authority.Current.Spaces.Single(kept => kept.Id == space).Settings.Boosts);
    }

    [Fact]
    public void ASpaceKeepsNoMoreBoostsThanItsLimitButStillReplacesOne() {
        var boosts = new SpaceBoosts([.. Enumerable.Range(0, SpaceBoosts.MaximumBoosts).Select(index => Boost($"site{index}.example"))]);

        var refusal = Assert.Throws<Rejected>(() => boosts.Setting(Boost("one-more.example")));
        Assert.Equal(new BoostLimitReached(SpaceBoosts.MaximumBoosts), refusal.Rejection);
        var replaced = boosts.Setting(Boost("site3.example", enabled: false));
        Assert.Equal(SpaceBoosts.MaximumBoosts, replaced.Sites.Count);
        Assert.False(replaced.Sites[3].IsEnabled);
    }

    [Fact]
    public void BoostsAreSavedWithTheirSpaceAndReadBackFromTheSavedSession() {
        var (session, space, _) = SavedSession();
        using var device = new TestDevice(session["session"]!);
        device.Send(new SetSiteBoost(device.Workspace, space, Boost("example.com", css: "body { max-width: 70ch; }")));
        device.Send(new SetSiteBoost(device.Workspace, space, Boost("docs.example.org", enabled: false) with {
            IsDark = true,
            Font = null
        }));

        var saved = StoredSessionCodec.Encode(device.Authority.Current);
        using var reopened = new TestDevice(JsonNode.Parse(saved.ToJsonString())!);

        Assert.Equal(device.Authority.Current.Spaces.Single(kept => kept.Id == space).Settings.Boosts,
            reopened.Authority.Current.Spaces.Single(kept => kept.Id == space).Settings.Boosts);
        // A saved Space without Boosts writes none.
        Assert.DoesNotContain("boosts", StoredSessionCodec.Encode(StoredSessionCodec.DecodeSession(session["session"])).ToJsonString(),
            StringComparison.Ordinal);
    }

    [Fact]
    public void ASavedBoostThisBuildCannotFullyReadKeepsWhatItCan() {
        var boosts = StoredSessionCodec.DecodeBoosts(JsonNode.Parse("""
            [{"site":"Example.com","isDark":"yes","tintHue":"red","brightness":2,"font":"comic","hiddenSelectors":["#a",4],
              "customCSS":7,"futureMember":true},
             {"site":"example.com","isEnabled":false},
             {"isEnabled":true}, 3, {"site":"bad site"}]
            """));

        var boost = Assert.Single(boosts!.Sites);
        Assert.Equal(new SiteBoost("example.com", IsEnabled: true, IsDark: false, TintHue: 0, TintStrength: 0, SiteBoost.MaximumLevel, 1,
            Font: null, ["#a"], ""), boost);
        Assert.Null(StoredSessionCodec.DecodeBoosts(JsonValue.Create("not a list")));
    }

    [Fact]
    public void BoostsTravelThroughAnExportIntoTheSpaceAnImportMakes() {
        var (session, space, _) = SavedSession();
        using var device = new TestDevice(session["session"]!);
        device.Send(new SetSiteBoost(device.Workspace, space, Boost("example.com", hidden: ["#ads", "header .promo"])));
        device.Send(new SetSiteBoost(device.Workspace, space, Boost("docs.example.org", enabled: false) with { Font = null }));

        var exported = device.Query(new ExportWorkspace(device.Workspace, ExportFormat.BrowserData));
        string text = Encoding.UTF8.GetString(exported.Contents);
        using var folder = new BrowserDataFolder();
        var read = Assert.Single(ReadBrowserData(folder.Write(ExportFormat.BrowserData.FileName, text)));

        Assert.Contains($"\"schemaVersion\": {BrowserDataFile.SchemaVersion}", text, StringComparison.Ordinal);
        Assert.Equal(device.Authority.Current.Spaces.Single(kept => kept.Id == space).Settings.Boosts, read.Settings.Boosts);
        // A file from before Boosts reads as a Space without them.
        Assert.Null(Assert.Single(ReadBrowserData(ImportFixture("archive-current", "data.json"))).Settings.Boosts);
    }
}
