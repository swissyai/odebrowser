using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// The persistent workspace imports the old settings once and keeps the
/// preferences on this device; the launch plan reads its startup choice.
public sealed partial class BrowserContractsTests {
    private static LaunchPlan LaunchPlan(Guid workspace, DevicePlatform? platform = null, LaunchEnvironment? environment = null) =>
        new(workspace, platform ?? DevicePlatform.Desktop, environment ?? LaunchEnvironment.Installed);

    private static LegacyAppPreferences LegacyPreferences() => new(StartupBehavior: "lastActiveTab", OffersTranslation: false,
        AutomaticallyTranslates: true, TranslationRules: """{"sources":{"es":{"isEnabled":true,"targetID":"en"}}}""",
        ChecksSpelling: true, AutomaticallyEntersPictureInPicture: false, SavedTabClosePolicy: "returnToSavedURL",
        SavedTabFaviconReturnsToSavedUrl: true, SplitFocusFollowsMouse: true);

    [Fact]
    public void LegacyPreferencesImportOnceAndPersistWithTheSession() {
        var session = SavedSession().Document["session"]!;
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var authority = device.Authority;
            device.Send(new AdoptSetupCompletion(Completed: true));
            Assert.Equal(StartupBehavior.ShowStartPage, device.Query(LaunchPlan(device.Workspace)).Startup);
            device.Send(new ImportAppPreferences(device.Workspace, LegacyPreferences()));
            saved = authority.Checkpoint().Read("core");
        }
        var stored = JsonNode.Parse(saved)!["appPreferences"]!;
        Assert.Equal("lastActiveTab", stored["startupBehavior"]!.GetValue<string>());
        Assert.False(stored["offersTranslation"]!.GetValue<bool>());
        Assert.True(stored["automaticallyTranslates"]!.GetValue<bool>());
        Assert.Equal("en", stored["translationRules"]!["sources"]!["es"]!["targetID"]!.GetValue<string>());
        Assert.True(stored["checksSpelling"]!.GetValue<bool>());
        Assert.False(stored["automaticallyEntersPictureInPicture"]!.GetValue<bool>());
        Assert.Equal("returnToSavedURL", stored["savedTabClosePolicy"]!.GetValue<string>());
        Assert.True(stored["savedTabFaviconReturnsToSavedURL"]!.GetValue<bool>());
        Assert.True(stored["splitFocusFollowsMouse"]!.GetValue<bool>());

        // A later launch finds the record and never imports over it again.
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority;
        var kept = restored.Current.AppPreferences;
        relaunched.Send(new ImportAppPreferences(relaunched.Workspace, new("showStartPage", null, null, null, false, null, null, null,
            null)));
        Assert.Same(kept, restored.Current.AppPreferences);
        relaunched.Send(new AdoptSetupCompletion(Completed: true));
        Assert.Equal(StartupBehavior.LastActiveTab, relaunched.Query(LaunchPlan(relaunched.Workspace)).Startup);
    }

    [Fact]
    public void UnreadableLegacyValuesKeepTheirDefaults() {
        using var device = new TestDevice(SavedSession().Document["session"]!);
        var authority = device.Authority;
        device.Send(new ImportAppPreferences(device.Workspace, new("retiredChoice", null, null, "not json", null, null, null, null, null)));
        var stored = authority.Current.AppPreferences!;
        Assert.Equal(AppPreferences.Default, stored);
    }

    [Fact]
    public void OnlyThePersistentWorkspaceKeepsAppPreferences() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var owner = device.Authority;
        var preferences = AppPreferences.Default with { ChecksSpelling = true };
        device.Send(new SetAppPreferences(device.Workspace, preferences));
        Assert.Equal(preferences, owner.Current.AppPreferences);

        var borrowed = device.Borrow(session["spaces"]![0]!);
        var privateWorkspace = device.Attach(session.DeepClone(), WorkspaceKind.Private);
        foreach (var workspace in new[] { borrowed, privateWorkspace }) {
            Assert.Equal(new PersistentWorkspaceRequired(workspace), Assert.Throws<Rejected>(() =>
                device.Send(new SetAppPreferences(workspace, preferences))).Rejection);
            Assert.Equal(new PersistentWorkspaceRequired(workspace), Assert.Throws<Rejected>(() =>
                device.Query(LaunchPlan(workspace))).Rejection);
        }
    }

    [Fact]
    public void TabPreviewChoicesKeepTheirSitesAndPersistWithTheSession() {
        var session = SavedSession().Document["session"]!;
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var authority = device.Authority;
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { ChecksSpelling = true }));
            Assert.Null(JsonNode.Parse(authority.Checkpoint().Read("core"))!["appPreferences"]!["tabPreviews"]);

            var previews = new TabPreviewPreferences(ShowsPreviews: false,
                ["Calendar.Google.com", "mail.google.com.", "www.example.com", "mail.google.com", "not a site", ""]);
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { TabPreviews = previews }));
            Assert.Equal(new TabPreviewPreferences(false, ["calendar.google.com", "example.com", "mail.google.com"]),
                authority.Current.AppPreferences!.TabPreviews);
            saved = authority.Checkpoint().Read("core");
        }
        var stored = JsonNode.Parse(saved)!["appPreferences"]!["tabPreviews"]!;
        Assert.False(stored["showsPreviews"]!.GetValue<bool>());
        Assert.Equal(3, stored["sitesWithoutPreviews"]!.AsArray().Count);

        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority.Current.AppPreferences!.TabPreviews;
        Assert.False(restored.ShowsPreviews);
        Assert.Equal(["calendar.google.com", "example.com", "mail.google.com"], restored.SitesWithoutPreviews);
    }

    /// Nesting tabs opened from pages is written only once chosen, and a saved
    /// session keeps it across a relaunch.
    [Fact]
    public void NestingTabsOpenedFromPagesPersistsWithTheSessionOnceChosen() {
        var session = SavedSession().Document["session"]!;
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var authority = device.Authority;
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default));
            Assert.Null(JsonNode.Parse(authority.Checkpoint().Read("core"))!["appPreferences"]!["nestsTabsOpenedFromPages"]);
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { NestsTabsOpenedFromPages = true }));
            saved = authority.Checkpoint().Read("core");
        }
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        Assert.True(relaunched.Authority.Current.AppPreferences!.NestsTabsOpenedFromPages);
    }

    /// Focus is written only once chosen; its limits keep one per site, within
    /// a day, and a saved session keeps them across a relaunch.
    [Fact]
    public void FocusChoicesKeepOneLimitPerSiteAndPersistWithTheSession() {
        var session = SavedSession().Document["session"]!;
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var authority = device.Authority;
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default));
            Assert.Null(JsonNode.Parse(authority.Checkpoint().Read("core"))!["appPreferences"]!["focus"]);

            var focus = new FocusPreferences(HidesFeeds: true, [
                new("www.YouTube.com", 30), new("reddit.com", 0), new("youtube.com", 45), new("not a site", 10),
                new("news.example", 5_000)
            ]);
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { Focus = focus }));
            Assert.Equal(new FocusPreferences(true, [new("news.example", 1_440), new("reddit.com", 1), new("youtube.com", 45)]),
                authority.Current.AppPreferences!.Focus);
            saved = authority.Checkpoint().Read("core");
        }
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority.Current.AppPreferences!.Focus!;
        Assert.True(restored.HidesFeeds);
        Assert.Equal(new SiteTimeLimit("youtube.com", 45), restored.LimitFor("youtube.com"));
        Assert.Null(restored.Limiting("youtube.com", null).LimitFor("youtube.com"));
    }

    [Fact]
    public void CloudReplacementNeverCarriesOrReplacesAppPreferences() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "lastActiveTab", ["futureChoice"] = 3 };
        var journal = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()))));
        var transition = Transition(journal, session.DeepClone(), new JsonArray(), replacing: true, now: 800000000.0);
        Assert.True(JsonNode.DeepEquals(session["appPreferences"], transition.Materialization["session"]!["appPreferences"]));
    }

    [Theory]
    [InlineData("desktop", false)]
    [InlineData("desktop", true)]
    [InlineData("mobile", false)]
    public void TheLaunchPlanReadsTheSavedStartupChoice(string platformName, bool gate) {
        var platform = DevicePlatform.Named(platformName)!;
        var session = SavedSession().Document["session"]!.AsObject();
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "lastActiveTab" };
        using (var device = new TestDevice(session)) {
            device.Send(new AdoptSetupCompletion(Completed: !gate));
            Assert.Equal(StartupBehavior.LastActiveTab, device.Query(LaunchPlan(device.Workspace, platform)).Startup);
        }
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "showStartPage" };
        using var shows = new TestDevice(session);
        shows.Send(new AdoptSetupCompletion(Completed: !gate));
        Assert.Equal(gate ? StartupBehavior.LastActiveTab : StartupBehavior.ShowStartPage,
            shows.Query(LaunchPlan(shows.Workspace, platform)).Startup);
        // Setup and isolated fixtures restore their staged tab; the mobile showcase always opens the Start Page.
        Assert.Equal(StartupBehavior.LastActiveTab, shows.Query(LaunchPlan(shows.Workspace, platform,
            LaunchEnvironment.Installed with { RequestsIsolatedSession = true })).Startup);
        Assert.Equal(StartupBehavior.ShowStartPage, shows.Query(LaunchPlan(shows.Workspace, DevicePlatform.Mobile,
            LaunchEnvironment.Installed with { PresentsShowcase = true })).Startup);
    }
}
