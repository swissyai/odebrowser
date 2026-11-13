using OdeCore.Contracts;

namespace OdeCore.Domain;

/// Nesting open tabs under one another, as `TabTree` lays them out.
public sealed partial class BrowserTabCollection {
    #region Actions - Trees

    /// Adds the new open tab `tab` nested under the open tab `parent`, after
    /// the tabs nested there already. A tab that shows reveals itself: every
    /// tab above it shows its nested tabs. Answers false, adding nothing, when
    /// `parent` is not here or cannot hold nested tabs, or `tab` is not open.
    public bool InsertNestedTab(BrowserTab tab, Guid parent, bool shows) {
        ArgumentNullException.ThrowIfNull(tab);
        var target = tabs.Find(candidate => candidate.Id == parent);
        if (target is null || !TabTree.Nests(target.State) || tab.Placement != TabPlacement.Current) return false;
        var nested = TabTree.Nested(TabStates, parent);
        var last = nested.Count > 0 ? Tab(nested[^1]) : target;
        tab.Nest(parent);
        InsertTab(tab, tabs.IndexOf(last) + 1);
        if (shows) Reveal(tab.Id);
        return true;
    }

    /// Nests the open tab `id` under the tab above it at its level, after the
    /// tabs nested there, which then show. Answers whether it nested: a tab
    /// first at its level, or one that cannot nest, stays.
    public bool IndentTab(Guid id) {
        var tab = Tab(id);
        var states = TabStates;
        var places = TabTree.Places(states);
        if (!places.TryGetValue(id, out var place)) return false;
        for (int above = tabs.IndexOf(tab) - 1; above >= 0; above--) {
            var candidate = states[above];
            if (!places.TryGetValue(candidate.Id, out var other)) {
                if (candidate.Placement == TabPlacement.Current && !candidate.IsStartPage) return false;
                continue;
            }
            if (other.Depth < place.Depth) return false;
            if (other.Depth > place.Depth) continue;
            tab.Nest(candidate.Id);
            tabs[above].CollapseNested(false);
            return true;
        }
        return false;
    }

    /// Moves the nested tab `id`, with the tabs nested under it, out one
    /// level: after the tabs nested under the tab it was nested under.
    /// Answers whether it moved: a tab at the top level stays.
    public bool OutdentTab(Guid id, DateTimeOffset now) {
        var tab = Tab(id);
        var places = TabTree.Places(TabStates);
        if (!places.TryGetValue(id, out var place) || place.ParentId is not { } parent) return false;
        var block = new HashSet<Guid>(TabTree.Nested(TabStates, id)) { id };
        var moving = tabs.Where(candidate => block.Contains(candidate.Id)).ToList();
        var remaining = tabs.Where(candidate => !block.Contains(candidate.Id)).ToList();
        int insertion = remaining.FindIndex(candidate => candidate.Id == parent) + 1
            + TabTree.Nested([.. remaining.Select(candidate => candidate.State)], parent).Count;
        remaining.InsertRange(insertion, moving);
        tabs.Clear();
        tabs.AddRange(remaining);
        tab.Nest(places[parent].ParentId);
        foreach (var moved in moving) moved.MarkPosition(now);
        return true;
    }

    /// Hides the tabs nested under the open tab `id` in the sidebar, or shows
    /// them. Answers whether anything changed: only a tab that holds nested
    /// tabs hides them.
    public bool CollapseNestedTabs(Guid id, bool collapsed) {
        var tab = Tab(id);
        if (tab.State.CollapsesNestedTabs == collapsed) return false;
        if (collapsed && TabTree.Nested(TabStates, id).Count == 0) return false;
        tab.CollapseNested(collapsed);
        return true;
    }

    /// Nests the selection under the open tab `parent`, after the tabs nested
    /// there already, each selected tab bringing the tabs nested under it and
    /// leaving its split. Refused with `InvalidFolderPlacement` for a selection
    /// that holds folders, a `parent` that cannot hold nested tabs, or one the
    /// selection holds or nests over.
    public void NestSelected(ResolvedSelection selection, Guid parent, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(selection);
        var target = Tab(parent);
        if (selection.HoldsFolders || !TabTree.Nests(target.State)) throw new Rejected(new InvalidFolderPlacement());
        var states = TabStates;
        var moving = selection.MemberIds.ToHashSet();
        foreach (var id in selection.MemberIds)
            if (TabTree.Nests(Tab(id).State)) moving.UnionWith(TabTree.Nested(states, id));
        if (moving.Contains(parent)) throw new Rejected(new InvalidFolderPlacement());
        var staying = TabTree.Nested(states, parent).Where(id => !moving.Contains(id)).ToList();
        int after = tabs.IndexOf(staying.Count > 0 ? Tab(staying[^1]) : target) + 1;
        Guid? before = tabs.Skip(after).FirstOrDefault(candidate => !moving.Contains(candidate.Id)) is { } next
            && next.Placement == TabPlacement.Current ? next.Id : null;
        FileSelected(selection, TabPlacement.Current, folder: null, before, beforeFolder: null, leavesSplits: true, now);
        foreach (var id in selection.MemberIds) {
            var tab = Tab(id);
            if (tab.State.ParentTabId is not { } own || !moving.Contains(own)) tab.Nest(parent);
        }
    }

    /// The tabs `members` bring along within the open tabs' top level: the
    /// tabs nested under each, however deep, that are not members themselves.
    private HashSet<Guid> NestedUnder(IEnumerable<BrowserTab> members, IReadOnlySet<Guid> memberIds) {
        var states = TabStates;
        var carried = new HashSet<Guid>();
        foreach (var member in members)
            if (TabTree.Nests(member.State))
                foreach (var id in TabTree.Nested(states, member.Id))
                    if (!memberIds.Contains(id)) carried.Add(id);
        return carried;
    }

    /// Nests `members` filed before `anchor` at the open tabs' top level where
    /// that tab nests: a member whose own tab above stays behind joins the
    /// anchor's, or the top level at the end of the list.
    private void NestFiled(IEnumerable<BrowserTab> members, IReadOnlySet<Guid> memberIds, Guid? anchor) {
        Guid? parent = anchor is { } landing && tabs.Find(candidate => candidate.Id == landing) is { } before
            && TabTree.Nests(before.State) ? before.State.ParentTabId : null;
        foreach (var member in members)
            if (member.State.ParentTabId is not { } own || !memberIds.Contains(own)) member.Nest(parent);
    }

    /// Shows the tab `id` wherever it nests: every tab above it shows its
    /// nested tabs.
    private void Reveal(Guid id) {
        var places = TabTree.Places(TabStates);
        var above = places.TryGetValue(id, out var place) ? place.ParentId : null;
        for (int steps = 0; above is { } ancestor && steps < TabTree.MaximumDepth; steps++) {
            Tab(ancestor).CollapseNested(false);
            above = places.TryGetValue(ancestor, out var ancestorPlace) ? ancestorPlace.ParentId : null;
        }
    }

    #endregion
}
