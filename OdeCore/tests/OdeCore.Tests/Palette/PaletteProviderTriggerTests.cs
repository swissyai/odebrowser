using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Actions - Provider Triggers

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void ExistingPalettePreferencesKeepTheirPreviousSpaceTrigger(bool tabEnabled) {
        var (session, space) = PaletteSession([]);
        session["appPreferences"] = new JsonObject {
            ["palette"] = new JsonObject { ["searchesSitesWithTab"] = tabEnabled }
        };
        using var device = new TestDevice(session);
        var answer = device.Query(Asking(device.Open(space), "$yt cats"));
        Assert.Equal(tabEnabled, answer.Entry?.Provider?.Name == "youTube");
    }

    [Fact]
    public void IndependentTriggerChoicesPersistAcrossRelaunch() {
        var (session, space) = PaletteSession([]);
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var preferences = AppPreferences.Default with {
                Palette = PalettePreferences.Default with {
                    SearchesSitesWithTab = true,
                    ProviderSpaceTrigger = SearchProviderSpaceTrigger.Off
                }
            };
            device.Send(new SetAppPreferences(device.Workspace, preferences));
            saved = device.Authority.Checkpoint().Read("core");
        }
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority.Current.AppPreferences!.Palette;
        Assert.True(restored.SearchesSitesWithTab);
        Assert.Equal(SearchProviderSpaceTrigger.Off, restored.ProviderSpaceTrigger);
        var window = relaunched.Open(space);
        Assert.Null(relaunched.Query(Asking(window, "$yt cats")).Entry);
        Assert.NotNull(relaunched.Query(Asking(window, "yt")).OfferedSearch);
    }

    [Fact]
    public void StoredPalettePreferencesKeepWhatTheyCanReadAndDefaultTheRest() {
        var defaults = PalettePreferences.Default;
        var read = StoredSessionCodec.DecodePalettePreferences(new JsonObject {
            ["layout"] = "blended",
            ["sources"] = new JsonArray(
                new JsonObject { ["source"] = "history", ["isEnabled"] = false, ["limit"] = 7 },
                new JsonObject { ["source"] = "notAKind", ["isEnabled"] = true },
                new JsonObject { ["source"] = "openTabs", ["limit"] = "many" },
                new JsonObject { ["source"] = "spaces", ["isEnabled"] = "yes", ["limit"] = 500 },
                "notAnObject"),
            ["showsTopHit"] = false,
            ["prefersOpenTabs"] = "false",
            ["completesInline"] = false,
            ["learnsChoices"] = false,
            ["searchesSitesWithTab"] = false,
            ["showsReasons"] = true,
            ["providerSpaceTrigger"] = "notATrigger"
        });
        Assert.Equal(PaletteLayout.Blended, read.Layout);
        Assert.Equal(PaletteSource.All.Count, read.Sources.Count);
        Assert.Equal(new PaletteSourceChoice(PaletteSource.History, IsEnabled: false, Limit: 7), read.Sources[0]);
        Assert.Equal(new PaletteSourceChoice(PaletteSource.OpenTabs, PaletteSource.OpenTabs.IsEnabledByDefault, Limit: null),
            read.Sources[1]);
        Assert.Equal(new PaletteSourceChoice(PaletteSource.Spaces, PaletteSource.Spaces.IsEnabledByDefault, Limit: null),
            read.Sources[2]);
        Assert.False(read.ShowsTopHit);
        Assert.Equal(defaults.PrefersOpenTabs, read.PrefersOpenTabs);
        Assert.False(read.CompletesInline);
        Assert.False(read.LearnsChoices);
        Assert.False(read.SearchesSitesWithTab);
        Assert.True(read.ShowsReasons);
        Assert.Equal(defaults.ProviderSpaceTrigger, read.ProviderSpaceTrigger);

        var empty = StoredSessionCodec.DecodePalettePreferences(null);
        Assert.Equal(defaults.Layout, empty.Layout);
        Assert.Equal(defaults.Sources, empty.Sources);
        Assert.Equal(defaults.SearchesSitesWithTab
            ? SearchProviderSpaceTrigger.PrefixedShortcut : SearchProviderSpaceTrigger.Off, empty.ProviderSpaceTrigger);
        Assert.Equal(SearchProviderSpaceTrigger.Shortcut, StoredSessionCodec.DecodePalettePreferences(
            new JsonObject { ["providerSpaceTrigger"] = "shortcut", ["searchesSitesWithTab"] = false }).ProviderSpaceTrigger);
    }

    #endregion
}
