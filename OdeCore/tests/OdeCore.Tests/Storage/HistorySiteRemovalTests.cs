using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void RemovingAHistorySiteErasesHotAndStoredVisitsAndTextInOnlyItsSpace() {
        using var directory = new StorageDirectory();
        var (app, engine, workspace, space, page, _) = StoredBrowsing(directory);
        using var disposal = app;
        foreach (string url in new[] { "https://www.news.example/a", "https://docs.news.example/b", "https://notnews.example/c" })
            Browse(app, engine, page, url, "Article");
        var other = Guid.NewGuid();
        var store = app.History!;
        store.Visit(other, Entry("https://news.example/a", "Other Space", Morning), Morning);
        store.RememberText(space, "https://docs.news.example/b", "cobaltneedle", Morning);
        // An address outside the session's hot list must be removed too.
        store.Visit(space, Entry("https://news.example/old", "Old", Morning), Morning);
        store.Flush();
        Assert.Single(store.Matching(space, "cobaltneedle", 10));

        app.Send(new RemoveHistorySite(workspace, space, "https://WWW.NEWS.EXAMPLE/a"));
        var kept = Listed(app, workspace, space).Places.Select(place => place.Url).ToArray();
        Assert.DoesNotContain("https://news.example/old", kept);
        Assert.DoesNotContain("https://docs.news.example/b", kept);
        Assert.Contains("https://notnews.example/c", kept);
        Assert.Contains("https://example.com/article", kept);
        Assert.Single(store.Places(other, null, 10).Places);
        Assert.Empty(store.Matching(space, "cobaltneedle", 10));
        Assert.DoesNotContain(app.Workspace(workspace).Current.Spaces.Single(s => s.Id == space).History,
            entry => entry.Url.Contains("news.example", StringComparison.Ordinal) && !entry.Url.Contains("notnews", StringComparison.Ordinal));

        app.Send(new SetSpaceAccess(workspace, space, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            app.Send(new RemoveHistorySite(workspace, space, "https://notnews.example/c"))).Rejection);
        Assert.Contains(store.Places(space, null, 10).Places, place => place.Url == "https://notnews.example/c");
    }
}
