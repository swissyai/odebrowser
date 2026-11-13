using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

#region Types

/// An engine tab group an extension made in a Space of the persistent
/// session, which the folder of the same identity shows, as the device store
/// keeps it so the folder follows the group after the next launch: the
/// engine whose pages it groups, and the group's own title and color, which
/// may differ from its folder's.
internal sealed record TabGroupRecord(Guid Id, Guid SpaceId, EngineKind Engine, string Title, TabGroupColor Color);

#endregion

/// What the device store holds: every saved window's record, the saved
/// windows the next launch reopens, back to front, the persistent session's
/// site permission choices in storage order and its site engine choices least
/// recent first, the person's shortcut choices and link preferences, the
/// unfinished manual setup it keeps for the next launch, whether this device
/// has completed setup, what it has adopted from an installed release, the
/// tab groups whose folders follow them, the site searches, what each
/// persistent Space's palette remembers, the agent preferences and the ended
/// downloads it keeps.
internal sealed record DeviceRecords(IReadOnlyList<SavedWindow> Windows, IReadOnlyList<Guid> Reopening,
    IReadOnlyList<SitePermissionRecord> SitePermissions, IReadOnlyList<SiteEngineChoice> SiteEngines, ShortcutOverrides Shortcuts,
    LinkPreferences Links, KeptSetupDraft? SetupDraft, bool SetupCompleted, IReadOnlySet<DeviceAdoption> Adopted,
    IReadOnlyList<TabGroupRecord> TabGroups, EngineKind? DefaultEngine = null) {
    #region Static Variables

    public static readonly DeviceRecords Empty = new([], [], [], [], ShortcutOverrides.None, LinkPreferences.Default,
        SetupDraft: null, SetupCompleted: false, new HashSet<DeviceAdoption>(), TabGroups: []);

    #endregion

    #region Variables

    /// What each persistent Space's palette remembers, by Space.
    public IReadOnlyDictionary<Guid, PaletteMemory> PaletteMemories { get; init; } = new Dictionary<Guid, PaletteMemory>();

    /// The device's search catalog, or null before the platform first restored it.
    public SearchCatalog? SearchCatalog { get; init; }

    /// Whether agents may use Ode, and what the person allowed them.
    public AgentPreferences Agents { get; init; } = AgentPreferences.Off;

    public IReadOnlyList<SetupImportOutcome> ImportOutcomes { get; init; } = [];

    /// The ended downloads of the persistent session's Spaces that no engine
    /// keeps itself, newest first.
    public IReadOnlyList<DownloadState> Downloads { get; init; } = [];

    /// The level ad blocking blocks at, or null before one was chosen or first
    /// answered.
    public ContentBlockingLevel? ContentBlockingLevel { get; init; }

    /// The filter lists the person turned on or off.
    public IReadOnlyDictionary<FilterList, bool> FilterListChoices { get; init; } = new Dictionary<FilterList, bool>();

    /// The persistent session's Spaces' sites where they block no ads or
    /// trackers, in the order they were added.
    public IReadOnlyList<SiteContentBlocking> BlockingSites { get; init; } = [];

    /// The filter lists the person added, in the order added.
    public IReadOnlyList<CustomFilterList> CustomFilterLists { get; init; } = [];

    /// The person's own filters.
    public string CustomFilters { get; init; } = "";

    #endregion

    #region Actions - Adoption

    /// These records, having adopted `adoption` too.
    public DeviceRecords Adopting(DeviceAdoption adoption) => this with { Adopted = new HashSet<DeviceAdoption>(Adopted) { adoption } };

    #endregion

    #region Actions - Equality

    public bool Equals(DeviceRecords? other) => other is not null
        && SameWindowsAndSites(other) && SameSetup(other) && SamePaletteAndAgents(other) && SameContentBlocking(other);

    public override int GetHashCode() => HashCode.Combine(Windows.Count, SitePermissions.Count, Adopted.Count);

    /// Whether the saved windows and the per-site choices and links match.
    private bool SameWindowsAndSites(DeviceRecords other) => Windows.SequenceEqual(other.Windows)
        && Reopening.SequenceEqual(other.Reopening)
        && SitePermissions.SequenceEqual(other.SitePermissions)
        && SiteEngines.SequenceEqual(other.SiteEngines)
        && DefaultEngine == other.DefaultEngine
        && Shortcuts.SameAs(other.Shortcuts)
        && Links.Equals(other.Links);

    /// Whether setup, adoptions, tab groups, downloads and import outcomes match.
    private bool SameSetup(DeviceRecords other) => KeptSetupDraft.Same(SetupDraft, other.SetupDraft)
        && SetupCompleted == other.SetupCompleted
        && Adopted.SetEquals(other.Adopted)
        && TabGroups.SequenceEqual(other.TabGroups)
        && Downloads.SequenceEqual(other.Downloads)
        && ImportOutcomes.SequenceEqual(other.ImportOutcomes);

    /// Whether the search catalog, agents and palette memories match; a memory
    /// matches only while it is the same instance.
    private bool SamePaletteAndAgents(DeviceRecords other) => Equals(SearchCatalog, other.SearchCatalog)
        && Agents.Equals(other.Agents)
        && PaletteMemories.Count == other.PaletteMemories.Count
        && PaletteMemories.All(entry => other.PaletteMemories.TryGetValue(entry.Key, out var memory) && ReferenceEquals(memory, entry.Value));

    /// Whether the content blocking level, filter lists and blocking sites match.
    private bool SameContentBlocking(DeviceRecords other) => ContentBlockingLevel == other.ContentBlockingLevel
        && FilterListChoices.Count == other.FilterListChoices.Count
        && FilterListChoices.All(entry => other.FilterListChoices.TryGetValue(entry.Key, out bool isOn) && isOn == entry.Value)
        && BlockingSites.SequenceEqual(other.BlockingSites)
        && CustomFilterLists.SequenceEqual(other.CustomFilterLists)
        && CustomFilters == other.CustomFilters;

    #endregion
}
