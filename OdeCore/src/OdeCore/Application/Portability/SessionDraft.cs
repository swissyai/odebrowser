using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

/// One window or Space another browser's session holds, as its reader found
/// it: the folders and tabs, with the folder identities the browser spells,
/// and the name, symbol, accent and look it gave the Space, where it gave
/// any. `Ordinal` counts the browser's windows or Spaces from one. A browser
/// that keeps a profile for each Space, as Arc does, names the folder of the
/// Space's own profile, `Profile`, when it is not the browser's first, and
/// one that identifies its Spaces names the Space's identity, `SourceId`. A
/// Space may bring the tabs the browser archived for it, `ArchivedTabs`, and
/// its history, `History`, in any order. Drafts that name one `Group` shared
/// one session where they came from, as the Spaces of one Arc profile or the
/// workspaces of one Zen profile do, and come in as one group.
internal sealed record SessionDraft(int Ordinal, string? Name, IReadOnlyList<SessionFolder> Folders, IReadOnlyList<SessionTab> Tabs,
    string? Symbol = null, SpaceAccent? Accent = null, SpaceBranding? Branding = null, string? Profile = null, string? SourceId = null,
    IReadOnlyList<SessionArchivedTab>? ArchivedTabs = null, IReadOnlyList<SessionHistoryEntry>? History = null,
    string? Group = null) {
    #region Static Variables

    /// The most tabs one window or Space brings.
    public const int MaximumTabs = BrowserDataSpace.MaximumTabs;

    private const string UntitledFolder = "Untitled Folder";
    /// The fewest tabs a split view shows.
    private const int MinimumSplitMembers = 2;

    #endregion

    #region Actions - Spaces

    /// The Spaces `drafts` make for `source`, a browser that names its own
    /// Spaces: each draft that holds a tab or a name, in order, named as the
    /// browser named it or else by `names`, with every record a new identity
    /// from `ids`. A tab with no usable time is dated `importedAt`. At most
    /// `room` Spaces come, each with the draft it came from; a draft past
    /// them, holding more than a Space keeps or naming a folder twice or out
    /// of place is left out in `leftOut`, with why. Of the drafts that name
    /// one `Group`, the first Space made leads and each later one is its
    /// Sub-Space.
    public static IReadOnlyList<(SpaceState Space, SessionDraft Draft)> Spaces(IReadOnlyList<SessionDraft> drafts, ImportSource source,
        ImportSpaceNames names, IIdSource ids, DateTimeOffset importedAt, int room, ICollection<ImportLeftOut> leftOut) {
        ArgumentNullException.ThrowIfNull(leftOut);
        var kept = drafts.Where(draft => draft.IsKept).ToArray();
        bool numbered = kept.Length > 1;
        List<(SpaceState, SessionDraft)> made = [];
        foreach (var draft in kept) {
            if (made.Count >= room) {
                leftOut.Add(new(draft.ShownName(names, numbered), new SessionOverLimits()));
                continue;
            }
            try {
                made.Add((draft.Space(source, names, numbered, ids, importedAt), draft));
            } catch (Rejected rejected) {
                leftOut.Add(new(draft.ShownName(names, numbered), rejected.Rejection));
            }
        }
        Dictionary<string, SpaceState> leaders = new(StringComparer.Ordinal);
        for (int index = 0; index < made.Count; index++) {
            var (space, draft) = made[index];
            if (draft.Group is not { } group) continue;
            if (leaders.TryGetValue(group, out var leader))
                made[index] = (space with { Membership = SpaceMembership.Joining(leader, importedAt) }, draft);
            else
                leaders[group] = space;
        }
        return made;
    }

    /// The places in `drafts` of those `Spaces` tries to make Spaces of with
    /// `room` for them: each that holds a tab or a name, while room remains,
    /// and holds no more tabs than a Space keeps.
    public static IReadOnlyList<int> Imported(IReadOnlyList<SessionDraft> drafts, int room) {
        ArgumentNullException.ThrowIfNull(drafts);
        List<int> imported = [];
        int tried = 0;
        for (int index = 0; index < drafts.Count && tried < room; index++) {
            if (!drafts[index].IsKept) continue;
            tried++;
            if (drafts[index].Tabs.Count <= MaximumTabs) imported.Add(index);
        }
        return imported;
    }

    /// One Space holding the tabs of a profile's windows, `drafts`: the first
    /// window that holds a tab, joined by each later one that fits beside it,
    /// each made as `Spaces` makes them. Null when no window holds a tab. A
    /// window a Space would not keep or that does not fit is skipped, and
    /// `problem` says why the last one was.
    public static SpaceState? Merged(IReadOnlyList<SessionDraft> drafts, ImportSource source, ImportSpaceNames names, IIdSource ids,
        DateTimeOffset importedAt, out Rejection? problem) {
        problem = null;
        var kept = drafts.Where(draft => draft.Tabs.Count > 0).ToArray();
        SpaceState? merged = null;
        foreach (var draft in kept) {
            if (merged is not null && merged.Tabs.Count + draft.Tabs.Count > MaximumTabs) {
                problem = new SessionOverLimits();
                continue;
            }
            SpaceState window;
            try {
                window = draft.Space(source, names, numbered: kept.Length > 1, ids, importedAt);
            } catch (Rejected rejected) {
                problem = rejected.Rejection;
                continue;
            }
            if (merged is null) {
                merged = window;
            } else if (merged.Folders.Count + window.Folders.Count > FolderTree.MaximumCount) {
                problem = new SessionOverLimits();
            } else {
                merged = merged with { Folders = [.. merged.Folders, .. window.Folders], Tabs = [.. merged.Tabs, .. window.Tabs] };
            }
        }
        return merged;
    }

    /// The Space this draft makes. Throws `Rejected` with `SessionOverLimits`
    /// when it holds more than a Space keeps, and `SessionUnrecognized` for a
    /// folder it names twice or cannot place.
    private SpaceState Space(ImportSource source, ImportSpaceNames names, bool numbered, IIdSource ids, DateTimeOffset importedAt) {
        if (Tabs.Count > MaximumTabs) throw new Rejected(new SessionOverLimits());
        var portable = Portable(source, names, numbered, ids, importedAt);
        try {
            return portable.Materialize(ids, importedAt);
        } catch (Rejected rejected) when (rejected.Rejection is ArchiveInvalid) {
            throw new Rejected(new SessionOverLimits());
        }
    }

    /// Whether the draft makes a Space: it holds a tab or a name.
    private bool IsKept => Tabs.Count > 0 || Name is not null;

    /// The name the Space shows: the browser's, or else its name from
    /// `names`, numbered by its place when the browser brings several.
    private string ShownName(ImportSpaceNames names, bool numbered) => ImportText.Title(Name, Fallback(names, numbered));

    private string Fallback(ImportSpaceNames names, bool numbered) => numbered
        ? names.NumberedSpaceName.Replace("%lld", Ordinal.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal)
        : names.SpaceName;

    /// The Space as an Ode browser-data file would keep it. Pinned tabs past
    /// the limit become saved tabs in an `Imported Pinned Tabs` folder, or
    /// outside any folder when the Space holds as many as it keeps.
    private BrowserDataSpace Portable(ImportSource source, ImportSpaceNames names, bool numbered, IIdSource ids,
        DateTimeOffset importedAt) {
        var (folders, folderIds) = PortableFolders(ids);
        var folderPlaces = folders.ToDictionary(folder => folder.Id, folder => folder.Location);
        var overflow = new ImportOverflow([], folder: null, spill => {
            if (folders.Count >= FolderTree.MaximumCount) return null;
            var made = ids.Next();
            folders.Add(Folder(made, NativeWorkspaceImport.OverflowFolderTitle, NativeWorkspaceImport.OverflowFolderSymbol, parent: null, spill));
            folderPlaces[made] = spill;
            return made;
        });
        var ordered = Gathered(Tabs);
        List<BrowserDataTab> tabs = [.. ordered.Select(tab => PortableTab(tab, folderIds, folderPlaces, overflow, ids, importedAt))];
        var splits = Split(ordered, tabs, ids);

        string name = ImportText.Bounded(Name, Fallback(names, numbered), ImportText.MaximumSpaceName)
            ?? throw new Rejected(new SessionOverLimits());
        string symbol = Symbol ?? source.Symbol;
        return new(name, symbol, Accent ?? source.Accent, Branding ?? SpaceBranding.NeutralImport(symbol), Ordered(folders), tabs,
            splits, Archive(ids), Visits(), StoredSessionCodec.DefaultBrowsingPreferences, SelectedTabId: null);
    }

    /// The Space's folders as an Ode browser-data file keeps them, each
    /// under a new identity, and the identity each source folder took.
    /// Rejects more folders than a Space keeps, a folder that repeats or
    /// names an unknown or its own parent, an overlong title or a cycle.
    private (List<BrowserDataFolder> Folders, Dictionary<string, Guid> Ids) PortableFolders(IIdSource ids) {
        if (Folders.Count > FolderTree.MaximumCount) throw new Rejected(new SessionOverLimits());
        Dictionary<string, Guid> folderIds = new(StringComparer.Ordinal);
        foreach (var folder in Folders)
            if (!folderIds.TryAdd(folder.SourceId, ids.Next())) throw new Rejected(new SessionUnrecognized());
        List<BrowserDataFolder> folders = [.. Folders.Select(folder => {
            Guid? parent = null;
            if (folder.ParentSourceId is { } parentSource)
                parent = parentSource != folder.SourceId && folderIds.TryGetValue(parentSource, out var mapped) ? mapped
                    : throw new Rejected(new SessionUnrecognized());
            string title = ImportText.Bounded(folder.Title, UntitledFolder, ImportText.MaximumFolderTitle)
                ?? throw new Rejected(new SessionOverLimits());
            return Folder(folderIds[folder.SourceId], title, FolderState.DefaultSymbol, parent, folder.Placement, folder.Color?.Color);
        })];
        if (!IsForest(folders)) throw new Rejected(new SessionOverLimits());
        return (folders, folderIds);
    }

    /// `tab` as an Ode browser-data file keeps it, in its folder while it
    /// stays in the folder's place, or past its section's limit in the
    /// section and folder `overflow` gives it. Rejects a saved tab whose
    /// folder is unknown and an overlong title.
    private static BrowserDataTab PortableTab(SessionTab tab, Dictionary<string, Guid> folderIds,
        Dictionary<Guid, TabPlacement> folderPlaces, ImportOverflow overflow, IIdSource ids, DateTimeOffset importedAt) {
        Guid? folder = tab.FolderSourceId is { } folderSource && folderIds.TryGetValue(folderSource, out var mapped) ? mapped : null;
        if (tab.Placement == TabPlacement.Saved && tab.FolderSourceId is not null && folder is null)
            throw new Rejected(new SessionUnrecognized());
        var (placement, spilled, overflowFolder) = overflow.Place(tab.Placement);
        if (spilled) folder = overflowFolder;
        string title = ImportText.Bounded(tab.Title, tab.Address.Host, ImportText.MaximumTitle)
            ?? throw new Rejected(new SessionOverLimits());
        string url = tab.Address.Spelling;
        bool fits = folder is { } held && folderPlaces.TryGetValue(held, out var place) && place == placement;
        return new(ids.Next(), title, NativeContent: null, url, placement.IsDurable ? url : null,
            placement.ImportedSymbol ?? TabIconMode.WebSymbol, placement,
            fits ? folder : null, SplitGroupId: null, tab.LastActivatedAt ?? importedAt);
    }

    /// The archived tabs the Space keeps: the most recently archived, as many
    /// as a Space keeps, oldest first as an archive lists them, each closed in
    /// the browser. A tab whose title a Space would not keep is left out.
    private List<BrowserDataArchivedTab> Archive(IIdSource ids) {
        var titled = (ArchivedTabs ?? [])
            .Select(archived => (Archived: archived, Title: ImportText.Bounded(archived.Title, archived.Address.Host, ImportText.MaximumTitle)))
            .Where(found => found.Title is not null && IsStored(found.Archived.Address.Spelling, removesFragment: false))
            .OrderBy(found => found.Archived.ArchivedAt)
            .TakeLast(BrowserDataSpace.MaximumTabs);
        return [.. titled.Select(found => new BrowserDataArchivedTab(new BrowserDataTab(ids.Next(), found.Title!, NativeContent: null,
            found.Archived.Address.Spelling, SavedUrl: null, TabIconMode.WebSymbol, TabPlacement.Current, FolderId: null,
            SplitGroupId: null, found.Archived.ArchivedAt), found.Archived.ArchivedAt, ArchiveReason.Closed))];
    }

    /// The history the Space keeps: each address once, its visits counted
    /// together, at most as many as a visit count holds, and titled as on its
    /// latest visit; the most recently visited, as many as a Space keeps. An
    /// address whose title a Space would not keep is left out.
    private List<BrowserDataHistoryEntry> Visits() {
        Dictionary<string, BrowserDataHistoryEntry> merged = new(StringComparer.Ordinal);
        foreach (var entry in History ?? []) {
            string url = entry.Address.Spelling;
            if (ImportText.Bounded(entry.Title, entry.Address.Host, ImportText.MaximumTitle) is not { } title
                || !IsStored(url, removesFragment: true)) continue;
            int visits = (int)Math.Clamp(entry.VisitCount, 1, BrowserDataHistoryEntry.MaximumVisitCount);
            if (!merged.TryGetValue(url, out var existing)) {
                merged[url] = new(url, title, entry.LastVisitedAt, entry.LastVisitedAt, visits);
                continue;
            }
            bool later = entry.LastVisitedAt > existing.LastVisitedAt;
            merged[url] = new(url, later ? title : existing.Title,
                entry.LastVisitedAt < existing.FirstVisitedAt ? entry.LastVisitedAt : existing.FirstVisitedAt,
                later ? entry.LastVisitedAt : existing.LastVisitedAt,
                (int)Math.Min((long)existing.VisitCount + visits, BrowserDataHistoryEntry.MaximumVisitCount));
        }
        return [.. merged.Values.OrderByDescending(entry => entry.LastVisitedAt).ThenBy(entry => entry.Url, StringComparer.Ordinal)
            .Take(HistoryEntryState.MaximumEntries)];
    }

    /// Whether an Ode browser-data file reads `url` back as spelled.
    private static bool IsStored(string url, bool removesFragment) =>
        ImportAddress.TryReadStored(url, removesFragment, out var address) && address is not null;

    /// The split views of the browser's tabs that Ode keeps, joining their
    /// tabs in `tabs`: each whose tabs sit side by side, in one place and
    /// folder, at least two and no more than a split holds. The tabs of any
    /// other show on their own.
    private static List<BrowserDataSplit> Split(IReadOnlyList<SessionTab> sources, List<BrowserDataTab> tabs, IIdSource ids) {
        Dictionary<string, Guid> splitIds = new(StringComparer.Ordinal);
        Guid? Group(SessionTab tab) => tab.SplitSourceId is not { } source ? null
            : splitIds.TryGetValue(source, out var id) ? id : splitIds[source] = ids.Next();
        var asked = sources.Select(Group).ToArray();
        var kept = SplitMember.Repair([.. tabs.Select((tab, index) => new SplitMember(asked[index], tab.Placement, tab.FolderId))]);
        var counts = kept.OfType<Guid>().GroupBy(group => group).ToDictionary(group => group.Key, group => group.Count());
        List<BrowserDataSplit> splits = [];
        for (int index = 0; index < tabs.Count; index++) {
            Guid? group = kept[index] is { } joined && joined == asked[index] && counts[joined] >= MinimumSplitMembers ? joined : null;
            tabs[index] = tabs[index] with { SplitGroupId = group };
            if (group is { } made && splits.All(split => split.Id != made))
                splits.Add(new BrowserDataSplit(made, CustomTitle: null, TitleModifiedAt: null, CustomIconSymbol: null, IconModifiedAt: null,
                    Tint: null, TintModifiedAt: null));
        }
        return splits;
    }

    /// `tabs` in order, each split's tabs gathered beside its first, where the
    /// browser shows them together whatever their order in its file.
    private static IReadOnlyList<SessionTab> Gathered(IReadOnlyList<SessionTab> tabs) {
        List<SessionTab> ordered = new(tabs.Count);
        HashSet<string> placed = new(StringComparer.Ordinal);
        foreach (var tab in tabs) {
            if (tab.SplitSourceId is not { } split) {
                ordered.Add(tab);
            } else if (placed.Add(split)) {
                ordered.AddRange(tabs.Where(member => member.SplitSourceId == split));
            }
        }
        return ordered;
    }

    /// A folder in the default color, among the saved tabs unless `placement` says otherwise.
    private static BrowserDataFolder Folder(Guid id, string title, string symbol, Guid? parent, TabPlacement? placement = null,
        BrandColor? color = null) =>
        new(id, placement ?? TabPlacement.Saved, title, symbol, color ?? FolderState.DefaultColor, parent, IsCollapsed: false,
            OrderAnchorTabId: null);

    private static bool IsForest(IReadOnlyList<BrowserDataFolder> folders) {
        try {
            _ = new FolderTree([.. folders.Select(folder => folder.Materialize(folder.Id, folder.ParentId))]).DisplayOrder();
            return true;
        } catch (Exception error) when (error is BrowserRuleException or Rejected) {
            return false;
        }
    }

    /// `folders`, each parent before its children.
    private static IReadOnlyList<BrowserDataFolder> Ordered(IReadOnlyList<BrowserDataFolder> folders) {
        var order = new FolderTree([.. folders.Select(folder => folder.Materialize(folder.Id, folder.ParentId))]).DisplayOrder();
        var byId = folders.ToDictionary(folder => folder.Id);
        return [.. order.Select(folder => byId[folder.Id])];
    }

    #endregion
}
