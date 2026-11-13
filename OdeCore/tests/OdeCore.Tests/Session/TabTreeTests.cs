using System.Text;
using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// Open tabs nested under the tab they were opened from: where a nested tab
/// opens, what the sidebar lists and shows, what closing, moving, dropping,
/// indenting and outdenting do to a tree, and that a tree survives the saved
/// session and an export.
public sealed partial class BrowserContractsTests {
    #region Types

    /// One Space with a pinned tab and four open tabs, A to D, shown in a window.
    private sealed class TreeSpace : IDisposable {
        public Guid Space { get; } = Guid.NewGuid();
        public Guid P { get; } = Guid.NewGuid();
        public Guid A { get; } = Guid.NewGuid();
        public Guid B { get; } = Guid.NewGuid();
        public Guid C { get; } = Guid.NewGuid();
        public Guid D { get; } = Guid.NewGuid();
        public TestDevice Device { get; }
        public Guid Window { get; }

        public TreeSpace() {
            var session = SavedSession().Document["session"]!;
            session.AsObject().Remove("disposableSeedMarker");
            session.AsObject().Remove("selectedSpaceID");
            var space = session["spaces"]![0]!.AsObject();
            space["id"] = SwiftId(Space);
            space["tabs"] = new JsonArray(Tab(P, "pinned"), Tab(A, "current"), Tab(B, "current"), Tab(C, "current"),
                Tab(D, "current"));
            space["folders"] = new JsonArray();
            space["splitGroups"] = new JsonArray();
            space.Remove("selectedTabID");
            Device = new TestDevice(session);
            Window = Device.Open(Space, (Space, A));
            Device.Send(new SetAppPreferences(Device.Workspace, AppPreferences.Default with { NestsTabsOpenedFromPages = true }));
        }

        public SpaceState State => Device.Authority.Current.Spaces.Single(space => space.Id == Space);

        /// The open tabs in order, each with how deep it nests.
        public (Guid Id, int Depth)[] Open => [.. State.Sidebar.Lists.Single(list => list.FolderId is null
            && list.Section == TabPlacement.Current).Rows.Select(row => (row.Id, row.TreeDepth))];

        public Guid? Parent(Guid tab) => State.Tabs.Single(kept => kept.Id == tab).ParentTabId;

        /// Opens a page in a new tab from the page of `opener`, shown when `shows`.
        public Guid OpenUnder(Guid opener, bool shows = false) {
            var id = Guid.NewGuid();
            Device.Send(new OpenTab(Device.Workspace, Window, Space, id, new TabContent($"https://tree.example/{id}", null, "Page"),
                TabPlacement.Current, AfterTabId: opener, shows, OpenerTabId: opener));
            return id;
        }

        public void Dispose() => Device.Dispose();

        private static JsonObject Tab(Guid id, string placement) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = $"https://tree.example/{id}",
            ["placement"] = placement,
            ["savedURL"] = placement == "current" ? null : $"https://tree.example/{id}",
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0
        };
    }

    #endregion

    #region Tests

    /// A tab a page opens nests under the tab of that page, after the tabs
    /// nested there already, as deep as it goes, and the sidebar lists each
    /// with its depth and how many tabs nest under it.
    [Fact]
    public void ATabOpenedFromAPageNestsAfterTheTabsAlreadyNestedThere() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.A);
        var y = f.OpenUnder(f.A);
        var z = f.OpenUnder(x);

        Assert.Equal([(f.A, 0), (x, 1), (z, 2), (y, 1), (f.B, 0), (f.C, 0), (f.D, 0)], f.Open);
        Assert.Equal(f.A, f.Parent(x));
        Assert.Equal(x, f.Parent(z));
        var rows = f.State.Sidebar.Lists.Single(list => list.FolderId is null && list.Section == TabPlacement.Current).Rows;
        Assert.Equal(3, rows.Single(row => row.Id == f.A).NestedTabs);
        Assert.Equal(1, rows.Single(row => row.Id == x).NestedTabs);

        // A pinned tab holds no nested tabs: what it opens opens as before.
        var loose = f.OpenUnder(f.P);
        Assert.Null(f.Parent(loose));

        // Without the preference, the opener nests nothing: the tab opens where
        // AfterTabId puts it.
        f.Device.Send(new SetAppPreferences(f.Device.Workspace, AppPreferences.Default));
        var after = f.OpenUnder(f.B);
        Assert.Null(f.Parent(after));
        Assert.Equal(f.B, f.Open[f.Open.ToList().FindIndex(row => row.Id == after) - 1].Id);
    }

    /// Closing a tab moves the tabs nested under it up one level, in place,
    /// whether or not it hid them; Reopen brings the tab back unnested.
    [Fact]
    public void ClosingATabMovesTheTabsNestedUnderItUpOneLevel() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.A);
        var z = f.OpenUnder(x);
        var y = f.OpenUnder(f.A);

        f.Device.Send(new CloseTab(f.Device.Workspace, f.Window, f.Space, x));
        Assert.Equal([(f.A, 0), (z, 1), (y, 1), (f.B, 0), (f.C, 0), (f.D, 0)], f.Open);
        Assert.Equal(f.A, f.Parent(z));

        f.Device.Send(new CollapseNestedTabs(f.Device.Workspace, f.Space, f.A, Collapsed: true));
        f.Device.Send(new CloseTab(f.Device.Workspace, f.Window, f.Space, f.A));
        Assert.Equal([(z, 0), (y, 0), (f.B, 0), (f.C, 0), (f.D, 0)], f.Open);
        Assert.All(f.State.Sidebar.Lists.SelectMany(list => list.Rows), row => Assert.False(row.IsHiddenInTree));
    }

    /// A collapsed tab hides the tabs nested under it from what a person sees
    /// and steps through, while the sidebar still lists them. A tab that opens
    /// shown under it shows them again; one that opens behind it keeps them hidden.
    [Fact]
    public void CollapsingHidesNestedTabsUntilOneOpensShownThere() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.A);
        var z = f.OpenUnder(x);

        f.Device.Send(new CollapseNestedTabs(f.Device.Workspace, f.Space, f.A, Collapsed: true));
        var state = f.State;
        var rows = state.Sidebar.Lists.Single(list => list.FolderId is null && list.Section == TabPlacement.Current).Rows;
        Assert.True(rows.Single(row => row.Id == f.A).CollapsesNestedTabs);
        Assert.True(rows.Single(row => row.Id == x).IsHiddenInTree);
        Assert.True(rows.Single(row => row.Id == z).IsHiddenInTree);
        var shown = state.Sidebar.Shown(state.Folders, _ => true).ToArray();
        Assert.DoesNotContain(x, shown);
        Assert.DoesNotContain(z, shown);
        Assert.DoesNotContain(state.Sidebar.Stops(state.Folders, _ => true), stop => stop.Id == x);
        Assert.Contains(x, state.Sidebar.Positions().Keys);

        f.OpenUnder(f.A);
        Assert.True(f.State.Tabs.Single(tab => tab.Id == f.A).CollapsesNestedTabs);
        f.OpenUnder(z, shows: true);
        Assert.False(f.State.Tabs.Single(tab => tab.Id == f.A).CollapsesNestedTabs);
        Assert.False(f.State.Tabs.Single(tab => tab.Id == x).CollapsesNestedTabs);

        // A tab with nothing nested under it has nothing to hide.
        f.Device.Send(new CollapseNestedTabs(f.Device.Workspace, f.Space, f.D, Collapsed: true));
        Assert.False(f.State.Tabs.Single(tab => tab.Id == f.D).CollapsesNestedTabs);
    }

    /// A tab dropped in the open tabs brings the tabs nested under it and nests
    /// as the tab it lands before does; dropped at the end it is at the top
    /// level. A tab never drops among the tabs nested under it.
    [Fact]
    public void ADroppedTabBringsItsNestedTabsAndNestsWhereItLands() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.A);
        var y = f.OpenUnder(f.A);
        TabSelection Lifting(Guid tab) => new([tab], [], [tab]);
        void Drop(Guid tab, Guid? before) => f.Device.Send(new DropIntoList(f.Device.Workspace, f.Window, f.Space, Lifting(tab),
            TabPlacement.Current, FolderId: null, before, BeforeFolderId: null));

        Drop(f.A, f.D);
        Assert.Equal([(f.B, 0), (f.C, 0), (f.A, 0), (x, 1), (y, 1), (f.D, 0)], f.Open);

        Drop(f.B, x);
        Assert.Equal([(f.C, 0), (f.A, 0), (f.B, 1), (x, 1), (y, 1), (f.D, 0)], f.Open);
        Assert.Equal(f.A, f.Parent(f.B));

        Drop(y, before: null);
        Assert.Equal([(f.C, 0), (f.A, 0), (f.B, 1), (x, 1), (f.D, 0), (y, 0)], f.Open);

        var refusal = f.Device.Query(new CanSend(new DropIntoList(f.Device.Workspace, f.Window, f.Space, Lifting(f.A),
            TabPlacement.Current, FolderId: null, x, BeforeFolderId: null))).Refusal;
        Assert.IsType<InvalidFolderPlacement>(refusal);
    }

    /// Dropping on an open tab nests the lift there, last, with what it holds;
    /// indenting nests a tab under the one above it at its level, and
    /// outdenting moves it out a level after the tabs nested where it was.
    [Fact]
    public void DroppingOnATabNestsTheLiftAndIndentOutdentStepALevel() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.C);
        f.Device.Send(new DropUnderTab(f.Device.Workspace, f.Window, f.Space, new([f.C], [], [f.C]), f.A));
        Assert.Equal([(f.A, 0), (f.C, 1), (x, 2), (f.B, 0), (f.D, 0)], f.Open);
        Assert.IsType<InvalidFolderPlacement>(f.Device.Query(new CanSend(new DropUnderTab(f.Device.Workspace, f.Window, f.Space,
            new([f.A], [], [f.A]), x))).Refusal);

        f.Device.Send(new IndentTab(f.Device.Workspace, f.Space, f.D));
        Assert.Equal([(f.A, 0), (f.C, 1), (x, 2), (f.B, 0), (f.D, 1)], f.Open);
        Assert.Equal(f.B, f.Parent(f.D));
        f.Device.Send(new IndentTab(f.Device.Workspace, f.Space, f.A));
        Assert.Null(f.Parent(f.A));

        f.Device.Send(new OutdentTab(f.Device.Workspace, f.Space, f.C));
        Assert.Equal([(f.A, 0), (f.C, 0), (x, 1), (f.B, 0), (f.D, 1)], f.Open);
        f.Device.Send(new OutdentTab(f.Device.Workspace, f.Space, f.C));
        Assert.Null(f.Parent(f.C));
    }

    /// While tabs nest, a lift may drop on any open tab it neither holds nor
    /// finds hidden under a collapsed tab.
    [Fact]
    public void ALiftNestsOnlyUnderOpenTabsItDoesNotHold() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.A);
        DropTargetList Lifting(Guid tab) => f.Device.Query(new DropTargets(f.Device.Workspace, f.Window, f.Space, new([tab], [], [tab])));

        Assert.Equal([f.B, f.C, f.D], Lifting(f.A).FolderAroundTabIds);
        Assert.Equal([f.A, x, f.C, f.D], Lifting(f.B).FolderAroundTabIds);
        f.Device.Send(new CollapseNestedTabs(f.Device.Workspace, f.Space, f.A, Collapsed: true));
        Assert.Equal([f.A, f.C, f.D], Lifting(f.B).FolderAroundTabIds);
    }

    /// A tab that leaves the open tabs' top level, pinned or filed in a
    /// folder, leaves the tabs nested under it, which move up a level.
    [Fact]
    public void PinningATabLeavesTheTabsNestedUnderIt() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.A);
        var z = f.OpenUnder(x);

        f.Device.Send(new TogglePin(f.Device.Workspace, f.Space, x));
        Assert.Equal(f.A, f.Parent(z));
        Assert.Null(f.Parent(x));
        Assert.Contains((z, 1), f.Open);
    }

    /// Nested tabs and the tabs that hide them survive the saved session and
    /// an export, under the new identities an import gives them; a file from
    /// before nesting nests nothing.
    [Fact]
    public void NestedTabsSurviveTheSavedSessionAndAnExport() {
        using var f = new TreeSpace();
        var x = f.OpenUnder(f.A);
        var z = f.OpenUnder(x);
        f.Device.Send(new CollapseNestedTabs(f.Device.Workspace, f.Space, x, Collapsed: true));

        var saved = StoredSessionCodec.DecodeTab(StoredSessionCodec.Encode(f.State.Tabs.Single(tab => tab.Id == x)));
        Assert.Equal(f.A, saved.ParentTabId);
        Assert.True(saved.CollapsesNestedTabs);

        var exported = f.Device.Query(new ExportWorkspace(f.Device.Workspace, ExportFormat.BrowserData));
        using var folder = new BrowserDataFolder();
        var read = ReadBrowserData(folder.Write(ExportFormat.BrowserData.FileName, Encoding.UTF8.GetString(exported.Contents)))
            .Single(space => space.Tabs.Count == f.State.Tabs.Count);
        var rows = read.Sidebar.Lists.Single(list => list.FolderId is null && list.Section == TabPlacement.Current).Rows;
        Assert.Equal([0, 1, 2, 0, 0, 0], rows.Select(row => row.TreeDepth));
        Assert.True(rows[1].CollapsesNestedTabs);
        Assert.True(rows[2].IsHiddenInTree);
        Assert.DoesNotContain(read.Tabs, tab => tab.Id == z);

        Assert.All(Assert.Single(ReadBrowserData(ImportFixture("archive-current", "data.json"))).Tabs,
            tab => Assert.Null(tab.ParentTabId));
    }

    /// The repair keeps only the links the order supports: a link to a tab
    /// that is gone, out of order, out of the open tabs' top level or round in
    /// a circle goes up to the nearest tab that still holds it, or the top level.
    [Fact]
    public void TreeRepairKeepsOnlyLinksTheOrderSupports() {
        static TabState Open(Guid id, Guid? parent = null, TabPlacement? placement = null) => new(id, "Page", "https://tree.example/",
            null, null, "globe", null, null, null, placement ?? TabPlacement.Current, null, null, DateTimeOffset.UnixEpoch, null, null,
            null, false, parent);
        Guid a = Guid.NewGuid(), b = Guid.NewGuid(), c = Guid.NewGuid(), d = Guid.NewGuid(), e = Guid.NewGuid(), gone = Guid.NewGuid();

        var repaired = TabTree.Normalize([Open(a), Open(b, a), Open(c, gone), Open(d, e), Open(e, d), Open(Guid.NewGuid(), a,
            TabPlacement.Saved)], new Dictionary<Guid, Guid?> { [gone] = b });

        // The circle breaks where it is met first: d goes to the top level, and e
        // nests under d, which comes just before it.
        Assert.Equal([null, a, b, null, d, null], repaired.Select(tab => tab.ParentTabId));
        Assert.Same(repaired, TabTree.Normalize(repaired));
    }

    #endregion
}
