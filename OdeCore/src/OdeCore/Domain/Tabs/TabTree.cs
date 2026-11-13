using OdeCore.Contracts;

namespace OdeCore.Domain;

/// <summary>
/// The trees open tabs form when one nests under another, as a tab opened from a
/// page does under the tab that opened it. Only an open tab at the top level of the
/// Open section, in no split, nests or holds nested tabs. A tab's nested tabs follow
/// it in its Space's tab order, each tree whole, and a link that order no longer
/// supports goes to the nearest tab above that still holds it, or to the top level:
/// the tabs nested under a tab that closes or moves away move up one level.
/// </summary>
public static class TabTree {
    #region Types

    /// <summary>A nesting tab's place in its tree: the tab it nests under, how many tabs
    /// it nests under, how many nest under it however deep, whether it hides them, and
    /// whether a collapsed tab above it hides it.</summary>
    public readonly record struct Place(Guid? ParentId, int Depth, int Nested, bool Collapses, bool IsHidden);

    #endregion

    #region Static Variables

    /// The most tabs one tab nests under. A link past it goes to the deepest tab
    /// allowed.
    public const int MaximumDepth = 16;

    #endregion

    #region Actions - Reading

    /// <summary>Whether <paramref name="tab"/> can nest under a tab or hold nested tabs:
    /// an open tab at the top level, in no split, that is not a Start Page.</summary>
    public static bool Nests(TabState tab) {
        ArgumentNullException.ThrowIfNull(tab);
        return tab.Placement == TabPlacement.Current && tab.FolderId is null && tab.SplitGroupId is null && !tab.IsStartPage;
    }

    /// <summary>The place of each tab of <paramref name="tabs"/> that nests, by identity,
    /// as the links <see cref="Normalize"/> keeps.</summary>
    public static Dictionary<Guid, Place> Places(IReadOnlyList<TabState> tabs) {
        ArgumentNullException.ThrowIfNull(tabs);
        var links = Links(tabs, Parents(tabs, formerParents: null));
        var places = new Dictionary<Guid, Place>();
        var chain = new List<(Guid Id, bool Collapses)>();
        for (int index = 0; index < tabs.Count; index++) {
            var tab = tabs[index];
            if (!Nests(tab)) {
                if (Interrupts(tab)) chain.Clear();
                continue;
            }
            if (links[index] is { } parent) {
                int at = chain.FindIndex(link => link.Id == parent);
                chain.RemoveRange(at + 1, chain.Count - at - 1);
            } else {
                chain.Clear();
            }
            foreach (var (ancestor, _) in chain) places[ancestor] = places[ancestor] with { Nested = places[ancestor].Nested + 1 };
            places[tab.Id] = new(links[index], chain.Count, 0, tab.CollapsesNestedTabs, chain.Any(link => link.Collapses));
            chain.Add((tab.Id, tab.CollapsesNestedTabs));
        }
        foreach (var (id, place) in places)
            if (place.Collapses && place.Nested == 0) places[id] = place with { Collapses = false };
        return places;
    }

    /// <summary>The tabs nested under <paramref name="id"/> in <paramref name="tabs"/>,
    /// however deep, in order.</summary>
    public static IReadOnlyList<Guid> Nested(IReadOnlyList<TabState> tabs, Guid id) {
        ArgumentNullException.ThrowIfNull(tabs);
        int start = -1;
        for (int index = 0; index < tabs.Count && start < 0; index++)
            if (tabs[index].Id == id) start = index;
        if (start < 0 || !Nests(tabs[start])) return [];
        var links = Links(tabs, Parents(tabs, formerParents: null));
        var tree = new HashSet<Guid> { id };
        var nested = new List<Guid>();
        for (int index = start + 1; index < tabs.Count; index++) {
            var tab = tabs[index];
            if (!Nests(tab)) {
                if (Interrupts(tab)) break;
                continue;
            }
            if (links[index] is not { } parent || !tree.Contains(parent)) break;
            tree.Add(tab.Id);
            nested.Add(tab.Id);
        }
        return nested;
    }

    #endregion

    #region Actions - Repair

    /// <summary><paramref name="tabs"/> with the links their order supports. A tab whose
    /// tab above is gone or no longer holds it nests under the nearest tab above that
    /// one, by its current link or, for a tab no longer in <paramref name="tabs"/>, by
    /// <paramref name="formerParents"/>, or goes to the top level. A tab that cannot
    /// nest keeps no link, and only a tab that holds nested tabs keeps them collapsed.
    /// Answers <paramref name="tabs"/> itself when nothing changes.</summary>
    public static IReadOnlyList<TabState> Normalize(IReadOnlyList<TabState> tabs,
        IReadOnlyDictionary<Guid, Guid?>? formerParents = null) {
        ArgumentNullException.ThrowIfNull(tabs);
        bool linked = false;
        foreach (var tab in tabs) linked |= tab.ParentTabId is not null || tab.CollapsesNestedTabs;
        if (!linked) return tabs;
        var links = Links(tabs, Parents(tabs, formerParents));
        var holding = new HashSet<Guid>();
        foreach (var link in links)
            if (link is { } parent) holding.Add(parent);
        TabState[]? normalized = null;
        for (int index = 0; index < tabs.Count; index++) {
            var tab = tabs[index];
            bool collapses = tab.CollapsesNestedTabs && holding.Contains(tab.Id);
            if (tab.ParentTabId == links[index] && tab.CollapsesNestedTabs == collapses) continue;
            normalized ??= [.. tabs];
            normalized[index] = tab with { ParentTabId = links[index], CollapsesNestedTabs = collapses };
        }
        return normalized ?? tabs;
    }

    #endregion

    #region Mutators

    /// The link each tab had, by identity: `formerParents` first, then each tab's
    /// own, which wins.
    private static Dictionary<Guid, Guid?> Parents(IReadOnlyList<TabState> tabs, IReadOnlyDictionary<Guid, Guid?>? formerParents) {
        var parents = formerParents is null ? new Dictionary<Guid, Guid?>() : new Dictionary<Guid, Guid?>(formerParents);
        foreach (var tab in tabs) parents[tab.Id] = tab.ParentTabId;
        return parents;
    }

    /// The tab each of `tabs` nests under, where its order supports it, walking
    /// up `parents` from a link it no longer supports.
    private static Guid?[] Links(IReadOnlyList<TabState> tabs, Dictionary<Guid, Guid?> parents) {
        var links = new Guid?[tabs.Count];
        // The tab before and every tab it nests under, outermost first.
        var chain = new List<Guid>();
        for (int index = 0; index < tabs.Count; index++) {
            var tab = tabs[index];
            if (!Nests(tab)) {
                if (Interrupts(tab)) chain.Clear();
                continue;
            }
            int at = -1;
            var candidate = tab.ParentTabId;
            for (int steps = 0; candidate is { } id && steps <= parents.Count; steps++) {
                at = chain.IndexOf(id);
                if (at >= 0) break;
                candidate = parents.GetValueOrDefault(id);
            }
            if (at >= 0) {
                at = Math.Min(at, MaximumDepth - 1);
                chain.RemoveRange(at + 1, chain.Count - at - 1);
                links[index] = chain[at];
            } else {
                chain.Clear();
            }
            chain.Add(tab.Id);
        }
        return links;
    }

    /// Whether `tab` ends the run of nesting tabs around it: an open tab the
    /// sidebar lists apart from them, in a folder or a split.
    private static bool Interrupts(TabState tab) => tab.Placement == TabPlacement.Current && !tab.IsStartPage && !Nests(tab);

    #endregion
}
