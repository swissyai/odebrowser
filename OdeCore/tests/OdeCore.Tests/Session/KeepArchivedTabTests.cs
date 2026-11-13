using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void KeepingAnArchivedTabRetainsItsIdentityWithoutShowingIt(bool pins) {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.Open));
        device.Send(new CloseTabs(device.Workspace, window, f.Space, Picking(f.Last)));
        var before = device.Authority.Current.Spaces[0];
        var archived = Assert.Single(before.ArchivedTabs, entry => entry.Tab.Id == f.Last);
        var selected = device.Tab(window, f.Space);

        device.Send(new KeepArchivedTab(device.Workspace, window, f.Space, before.ProfileId, f.Last, pins));

        var kept = device.Authority.Current.Spaces[0];
        var tab = Assert.Single(kept.Tabs, tab => tab.Id == f.Last);
        Assert.Equal(pins ? TabPlacement.Pinned : TabPlacement.Saved, tab.Placement);
        Assert.Equal(archived.Tab.Url, tab.SavedAddress);
        Assert.Equal(archived.Tab.Title, tab.Title);
        Assert.DoesNotContain(kept.ArchivedTabs, entry => entry.Tab.Id == f.Last);
        Assert.Equal(selected, device.Tab(window, f.Space));
        Assert.Equal(before.History, kept.History);
        var accepted = device.Authority.Current;
        Assert.IsType<UnknownArchivedTab>(Assert.Throws<Rejected>(() =>
            device.Send(new KeepArchivedTab(device.Workspace, window, f.Space, before.ProfileId, f.Last, pins))).Rejection);
        Assert.Same(accepted, device.Authority.Current);
    }

    [Fact]
    public void KeepingAnArchiveInAFullPinnedSectionFallsBackToSaved() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.Open));
        for (int index = 1; index < TabPlacement.PinnedCapacity; index++)
            device.Send(new OpenTab(device.Workspace, window, f.Space, Guid.NewGuid(),
                new TabContent($"http://127.0.0.1/pinned/{index}", null, "Pinned"), TabPlacement.Pinned, null, false));
        device.Send(new CloseTabs(device.Workspace, window, f.Space, Picking(f.Last)));
        device.Send(new KeepArchivedTab(device.Workspace, window, f.Space,
            device.Authority.Current.Spaces[0].ProfileId, f.Last, true));
        var space = device.Authority.Current.Spaces[0];
        Assert.Equal(TabPlacement.PinnedCapacity, space.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        Assert.Equal(TabPlacement.Saved, Assert.Single(space.Tabs, tab => tab.Id == f.Last).Placement);
        var linkId = Guid.NewGuid();
        device.Send(new KeepLink(device.Workspace, window, f.Space, space.ProfileId, f.Open,
            linkId, "http://127.0.0.1/kept", true));
        var link = Assert.Single(device.Authority.Current.Spaces[0].Tabs, tab => tab.Id == linkId);
        Assert.Equal(TabPlacement.Saved, link.Placement);
        Assert.Equal("http://127.0.0.1/kept", link.SavedAddress);
        Assert.Equal(f.Open, device.Tab(window, f.Space));
    }

    [Fact]
    public void KeepingLinksRejectsStaleProfilesMissingSourcesAndNonWebAddresses() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.Open));
        var space = device.Authority.Current.Spaces[0];
        var before = device.Authority.Current;
        KeepLink Keeping(Guid profile, Guid source, string address) => new(device.Workspace, window, f.Space,
            profile, source, Guid.NewGuid(), address, false);
        Assert.IsType<SelectionChanged>(Assert.Throws<Rejected>(() =>
            device.Send(Keeping(Guid.NewGuid(), f.Open, "http://127.0.0.1/kept"))).Rejection);
        Assert.IsType<SelectionChanged>(Assert.Throws<Rejected>(() =>
            device.Send(Keeping(space.ProfileId, Guid.NewGuid(), "http://127.0.0.1/kept"))).Rejection);
        Assert.IsType<UnsupportedAddress>(Assert.Throws<Rejected>(() =>
            device.Send(Keeping(space.ProfileId, f.Open, "javascript:alert(1)"))).Rejection);
        Assert.Same(before, device.Authority.Current);
        device.Send(new ShowSpace(window, f.Other));
        Assert.IsType<SelectionChanged>(Assert.Throws<Rejected>(() =>
            device.Send(Keeping(space.ProfileId, f.Open, "http://127.0.0.1/kept"))).Rejection);
        Assert.Same(before, device.Authority.Current);
    }

    [Fact]
    public void KeepingAnArchiveRejectsAWindowThatChangedSpaces() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.Open));
        device.Send(new CloseTabs(device.Workspace, window, f.Space, Picking(f.Last)));
        device.Send(new ShowSpace(window, f.Other));
        var before = device.Authority.Current;
        Assert.IsType<SelectionChanged>(Assert.Throws<Rejected>(() =>
            device.Send(new KeepArchivedTab(device.Workspace, window, f.Space,
                before.Spaces[0].ProfileId, f.Last, false))).Rejection);
        Assert.Same(before, device.Authority.Current);
    }
}
