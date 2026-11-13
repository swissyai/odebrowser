using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// The folder of the Chromium profile each Space an import brings was read
/// from, where the other browser keeps its sign-ins: named for every Space of
/// a browser built on Chromium, whether or not it offers extensions, never for
/// one that keeps no Chromium profile, and kept by the review.
public sealed partial class BrowserContractsTests {
    private const string ProfileBookmarks =
        """{"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"A","url":"https://a.example/"}]}}}""";

    [Fact]
    public void EachArcSpaceNamesTheProfileFolderItWasReadFromThroughTheReview() {
        using var arc = new BrowserDataFolder();
        string first = Path.Combine(arc.Path, "User Data", "Default"), second = Path.Combine(arc.Path, "User Data", "Profile 1");
        using var app = Importer();

        var imported = app.Query(new ReadImport(ImportSource.Arc, [
            new("arc", "Arc", null, ImportFixture("arc-rich", "StorableSidebar.json"), first)
        ]));

        // No profile keeps extension settings, so none is offered, yet each
        // Space names its folder: "Gradient" Arc's second profile, the others
        // its first, which they share.
        Assert.Empty(imported.Extensions);
        string[] expected = [.. imported.Spaces.Select(space => space.Settings.Name == "Gradient" ? second : first)];
        Assert.Equal(expected, imported.Spaces.Select(space => imported.Profiles!.Single(entry => entry.SpaceId == space.Id).ProfilePath));
        Assert.Contains(second, expected);
        Assert.True(expected.Count(path => path == first) > 1);

        using var device = new TestDevice(GuardedSession(withOpenSecondSpace: false));
        device.Send(new StartSetup(device.Workspace, SetupEntry.ImportBrowser));
        device.Send(new OfferImportSources([ImportSource.Arc]));
        device.Send(new ContinueImport());
        var review = Flowing(device.Send(new ReviewImport(ImportSource.Arc, imported.Spaces, [], imported.Extensions, imported.LeftOut,
            Profiles: imported.Profiles))).Review!;
        Assert.Equal(expected, review.Spaces.Select(space => space.SourceProfilePath));

        // An edit keeps it, even for a Space left out.
        review = Flowing(device.Send(new IncludeImportSpace(imported.Spaces[0].Id, Included: false))).Review!;
        Assert.Equal(expected, review.Spaces.Select(space => space.SourceProfilePath));
    }

    [Fact]
    public void EachChromeProfileSpaceNamesItsOwnFolderAndABrowserOffChromiumNamesNone() {
        using var chrome = new BrowserDataFolder();
        string work = chrome.Write(Path.Combine("Default", "Bookmarks"), ProfileBookmarks);
        string home = chrome.Write(Path.Combine("Profile 1", "Bookmarks"), ProfileBookmarks);
        using var app = Importer();

        var imported = app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Work", work, null, Path.Combine(chrome.Path, "Default")),
            new("Profile 1", "Home", home, null, Path.Combine(chrome.Path, "Profile 1"))
        ]));

        Assert.Empty(imported.Extensions);
        Assert.Equal([new ImportSpaceProfile(imported.Spaces[0].Id, Path.Combine(chrome.Path, "Default")),
            new ImportSpaceProfile(imported.Spaces[1].Id, Path.Combine(chrome.Path, "Profile 1"))], imported.Profiles!);

        // Safari keeps no Chromium profile, even when its profile names a folder.
        var safari = app.Query(new ReadImport(ImportSource.Safari, [
            new("safari", "Safari", ImportFixture("safari-profile", "Bookmarks.plist"), null, Path.Combine(chrome.Path, "Default"))
        ]));
        Assert.NotEmpty(safari.Spaces);
        Assert.Empty(safari.Profiles!);
    }

    [Fact]
    public void TheImportReviewNamesNoProfileFolderForASpaceReadFromNone() {
        using var device = new TestDevice(GuardedSession(withOpenSecondSpace: false));
        var spaces = ReadSpaces(ImportedSpace("Work", ImportedTab("https://mail.example/")),
            ImportedSpace("Home", ImportedTab("https://bank.example/")));
        string folder = Path.Combine("Chrome", "Default");
        device.Send(new StartSetup(device.Workspace, SetupEntry.ImportBrowser));
        device.Send(new OfferImportSources([ImportSource.Chrome]));
        device.Send(new ToggleImportSource(ImportSource.Chrome));
        device.Send(new ContinueImport());

        var review = Flowing(device.Send(new ReviewImport(ImportSource.Chrome, spaces, [],
            Profiles: [new(spaces[0].Id, folder)]))).Review!;

        Assert.Equal([folder, null], review.Spaces.Select(space => space.SourceProfilePath));
    }
}
