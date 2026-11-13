using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// The dated exports Ode keeps in a folder: each holds every format and
/// reads back as the workspace it wrote, only the newest seven stay, a
/// folder Ode did not write is never removed, a workspace with nothing a
/// person would miss writes none, and an export is written whole or not at
/// all.
public sealed partial class BrowserContractsTests {
    /// A workspace with folders, pinned, saved and open tabs, an archive and
    /// history, from the browser-data fixtures.
    private static TestDevice ExportedDevice() {
        var session = SavedSession().Document["session"]!;
        var device = new TestDevice(session);
        var window = device.Showing(session);
        var files = ReadBrowserData(ImportFixture("archive-current", "data.json"))
            .Concat(ReadBrowserData(ImportFixture("archive-split", "data.json"))).ToArray();
        device.Send(new ImportSpaces(device.Workspace, window, files));
        return device;
    }

    /// The names of the dated exports in `folder`, newest first.
    private static string[] ExportNames(string folder) =>
        [.. ExportFolder.List(folder).Select(path => Path.GetFileName(path))];

    private static string ExportName(DateTimeOffset at) =>
        TimeZoneInfo.ConvertTime(at, TimeZoneInfo.Local).ToString("yyyy-MM-dd HH.mm.ss", CultureInfo.InvariantCulture);

    [Fact]
    public void AnExportFolderHoldsEveryFormatAndReadsBackAsTheWorkspaceItWrote() {
        using var device = ExportedDevice();
        using var folder = new BrowserDataFolder();
        string target = Path.Combine(folder.Path, "Ode Export");

        var written = device.Query(new WriteExportFolder(device.Workspace, target));

        Assert.Equal(Path.Combine(target, ExportName(device.Clock.Now)), written.Path);
        Assert.Equal([.. ExportFormat.All.Select(format => format.FileName).Order(StringComparer.Ordinal)],
            Directory.EnumerateFiles(written.Path!).Select(Path.GetFileName).Order(StringComparer.Ordinal));
        Assert.Equal([Path.GetFileName(written.Path)!], Directory.EnumerateFileSystemEntries(target).Select(Path.GetFileName));

        var current = device.Authority.Current.Spaces;
        var spaces = ReadBrowserData(Path.Combine(written.Path!, ExportFormat.BrowserData.FileName));
        Assert.Equal(current.Select(space => space.Settings.Name), spaces.Select(space => space.Settings.Name));
        Assert.Contains(current, space => space.Tabs.Any(tab => tab.Placement == TabPlacement.Pinned));
        Assert.Contains(current, space => space.Folders.Count > 0);
        Assert.Contains(current, space => space.ArchivedTabs.Count > 0);
        for (int index = 0; index < current.Count; index++) {
            Assert.Equal(TabsOf(current[index]), TabsOf(spaces[index]));
            Assert.Equal(FoldersOf(current[index]), FoldersOf(spaces[index]));
            Assert.Equal(current[index].ArchivedTabs.Select(archived => (archived.Tab.Title, archived.Tab.Url)),
                spaces[index].ArchivedTabs.Select(archived => (archived.Tab.Title, archived.Tab.Url)));
            Assert.Equal(current[index].History.Select(entry => (entry.Url, entry.Title, entry.VisitCount)),
                spaces[index].History.Select(entry => (entry.Url, entry.Title, entry.VisitCount)));
        }

        string bookmarks = File.ReadAllText(Path.Combine(written.Path!, ExportFormat.Bookmarks.FileName));
        Assert.StartsWith("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n", bookmarks, StringComparison.Ordinal);

        var lines = File.ReadAllLines(Path.Combine(written.Path!, ExportFormat.History.FileName));
        Assert.Equal(current.Sum(space => space.History.Count), lines.Length);
        var first = current.First(space => space.History.Count > 0);
        var line = JsonNode.Parse(lines[0])!.AsObject();
        Assert.Equal(["firstVisitedAt", "lastVisitedAt", "space", "title", "url", "visitCount", "visits"], line.Select(member => member.Key));
        Assert.Equal((first.Settings.Name, first.History[0].Title, first.History[0].VisitCount),
            (line["space"]!.GetValue<string>(), line["title"]!.GetValue<string>(), line["visitCount"]!.GetValue<int>()));

        // Credentials, locks and profiles stay on the device.
        string all = string.Concat(Directory.EnumerateFiles(written.Path!).Select(File.ReadAllText));
        Assert.All(new[] { "credentialPreferences", "accessPolicy", "\"profile", "password" },
            key => Assert.DoesNotContain(key, all, StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void AFolderKeepsTheNewestSevenExportsAndNeverRemovesOneOdeDidNotWrite() {
        using var device = ExportedDevice();
        using var folder = new BrowserDataFolder();
        var start = device.Clock.Now;
        string foreign = folder.Write(Path.Combine(ExportName(start.AddDays(-30)), "notes.txt"), "kept");
        folder.Write(Path.Combine("Ode Browser Data.json"), "{}");

        List<string> names = [];
        for (int hour = 0; hour < 9; hour++) {
            device.Clock.Now = start.AddHours(hour);
            names.Add(Path.GetFileName(device.Query(new WriteExportFolder(device.Workspace, folder.Path)).Path!));
        }

        Assert.Equal(names.AsEnumerable().Reverse().Take(ExportFolder.Kept), ExportNames(folder.Path));
        Assert.True(File.Exists(foreign));
        Assert.True(File.Exists(Path.Combine(folder.Path, "Ode Browser Data.json")));
    }

    [Fact]
    public void TwoExportsInOneSecondEachKeepTheirOwnFolder() {
        using var device = ExportedDevice();
        using var folder = new BrowserDataFolder();

        string first = device.Query(new WriteExportFolder(device.Workspace, folder.Path)).Path!;
        string second = device.Query(new WriteExportFolder(device.Workspace, folder.Path)).Path!;

        Assert.Equal([ExportName(device.Clock.Now.AddSeconds(1)), ExportName(device.Clock.Now)], ExportNames(folder.Path));
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void AnUnchangedWorkspaceWritesNoExportUntilSomethingAPersonWouldMissChanges() {
        using var device = ExportedDevice();
        using var folder = new BrowserDataFolder();
        var written = device.Query(new WriteExportFolder(device.Workspace, folder.Path));

        var unchanged = device.Query(new WriteExportFolder(device.Workspace, folder.Path, written.Fingerprint));

        Assert.Null(unchanged.Path);
        Assert.Equal(written.Fingerprint, unchanged.Fingerprint);
        Assert.Single(ExportNames(folder.Path));

        // Open tabs and history change with every page; the daily export carries them.
        var spaces = device.Authority.Current.Spaces;
        var space = spaces[0];
        var open = space.Tabs.First() with { Id = Guid.NewGuid(), Placement = TabPlacement.Current, FolderId = null, Url = "https://open.example/" };
        Assert.Equal(written.Fingerprint, ExportFolder.Fingerprint([space with { Tabs = [.. space.Tabs, open], History = [] }, .. spaces.Skip(1)]));
        // A saved tab, a renamed Space and a smaller archive are each missed.
        var saved = open with { Placement = TabPlacement.Saved };
        Assert.NotEqual(written.Fingerprint, ExportFolder.Fingerprint([space with { Tabs = [.. space.Tabs, saved] }, .. spaces.Skip(1)]));
        Assert.NotEqual(written.Fingerprint, ExportFolder.Fingerprint(
            [space with { Settings = space.Settings with { Name = "Renamed" } }, .. spaces.Skip(1)]));
        var archived = spaces.First(candidate => candidate.ArchivedTabs.Count > 0);
        Assert.NotEqual(written.Fingerprint, ExportFolder.Fingerprint(
            [.. spaces.Select(candidate => candidate == archived ? candidate with { ArchivedTabs = [] } : candidate)]));
    }

    [Fact]
    public void AnExportIsWrittenWholeOrNotAtAll() {
        using var device = ExportedDevice();
        using var folder = new BrowserDataFolder();
        var kept = device.Query(new WriteExportFolder(device.Workspace, folder.Path)).Path!;
        // What an export that stopped partway left is never an export, and the next one clears it.
        string partial = folder.Write(Path.Combine(".ode-export-0123", ExportFormat.BrowserData.FileName), "{");
        Assert.Equal([Path.GetFileName(kept)], ExportNames(folder.Path));

        string file = folder.Write("not-a-folder", "");
        foreach (var target in new[] { file, "relative/Ode Export", "" })
            Assert.IsType<ExportFolderUnwritable>(Assert.Throws<Rejected>(() =>
                device.Query(new WriteExportFolder(device.Workspace, target))).Rejection);

        device.Clock.Now = device.Clock.Now.AddHours(1);
        device.Query(new WriteExportFolder(device.Workspace, folder.Path));
        Assert.False(Directory.Exists(Path.GetDirectoryName(partial)));
        Assert.Equal(2, ExportNames(folder.Path).Length);
        Assert.DoesNotContain(Directory.EnumerateDirectories(folder.Path), path => Path.GetFileName(path).StartsWith('.'));
    }

    [Fact]
    public void ALockedSpaceKeepsAnExportFromBeingWritten() {
        var session = GuardedSession();
        using var device = new TestDevice(session);
        using var folder = new BrowserDataFolder();
        string target = Path.Combine(folder.Path, "Ode Export");

        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Query(new WriteExportFolder(device.Workspace, target))).Rejection);
        Assert.False(Directory.Exists(target));

        Unlock(device.Send, device.Workspace, Identity(session).Space);
        Assert.NotNull(device.Query(new WriteExportFolder(device.Workspace, target)).Path);
    }
}
