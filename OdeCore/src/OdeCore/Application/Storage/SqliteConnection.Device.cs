using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

#region Types

/// Writes one part of `records` to the device store through `connection`,
/// given what the store was last written with, or null.
internal delegate void DevicePartWrite(SqliteConnection connection, DeviceRecords records, DeviceRecords? written);

#endregion

/// The device store: the tables beside the checkpoint table that keep the
/// device's own records, each read and written through a prepared
/// `SqliteStatement`.
internal sealed partial class SqliteConnection {
    #region Static Variables

    /// The device store's parts in the order a write visits them. Each one
    /// rewrites its records when nothing was written yet or when they differ
    /// from what was; palette memories and downloads compare row by row, and
    /// import outcomes are only added.
    private static readonly DevicePartWrite[] DeviceParts = [
        DevicePart(records => records.Windows, (now, was) => now.SequenceEqual(was), (connection, windows) => connection.WriteWindows(windows)),
        DevicePart(records => records.Reopening, (now, was) => now.SequenceEqual(was), (connection, windows) => connection.WriteReopening(windows)),
        DevicePart(records => records.SitePermissions, (now, was) => now.SequenceEqual(was),
            (connection, permissions) => connection.WriteSitePermissions(permissions)),
        DevicePart(records => records.SiteEngines, (now, was) => now.SequenceEqual(was), (connection, engines) => connection.WriteSiteEngines(engines)),
        DevicePart(records => records.DefaultEngine, (now, was) => now == was, (connection, engine) => connection.WriteDefaultEngine(engine)),
        DevicePart(records => records.Shortcuts, (now, was) => now.SameAs(was), (connection, shortcuts) => connection.WriteShortcuts(shortcuts)),
        DevicePart(records => records.Links, (now, was) => now.Equals(was), (connection, links) => connection.WriteLinks(links)),
        DevicePart(records => records.SetupDraft, KeptSetupDraft.Same, (connection, draft) => connection.WriteSetupDraft(draft)),
        DevicePart(records => records.SetupCompleted, (now, was) => now == was, (connection, completed) => connection.WriteSetupCompleted(completed)),
        DevicePart(records => records.Adopted, (now, was) => now.SetEquals(was), (connection, adopted) => connection.WriteAdoptions(adopted)),
        DevicePart(records => records.TabGroups, (now, was) => now.SequenceEqual(was), (connection, groups) => connection.WriteTabGroups(groups)),
        (connection, records, written) => connection.WritePaletteMemories(records.PaletteMemories, written?.PaletteMemories),
        DevicePart(records => records.SearchCatalog, (now, was) => ReferenceEquals(now, was), (connection, catalog) => connection.WriteSearchCatalog(catalog)),
        DevicePart(records => records.Agents, (now, was) => now.Equals(was), (connection, agents) => connection.WriteAgents(agents)),
        (connection, records, written) => connection.WriteDownloads(records.Downloads, written?.Downloads),
        (connection, records, written) => connection.WriteImportOutcomes(records.ImportOutcomes, written?.ImportOutcomes),
        DevicePart(records => records.ContentBlockingLevel, (now, was) => now == was,
            (connection, level) => connection.WriteContentBlockingLevel(level)),
        DevicePart(records => records.FilterListChoices, SameChoices, (connection, choices) => connection.WriteFilterListChoices(choices)),
        DevicePart(records => records.BlockingSites, (now, was) => now.SequenceEqual(was), (connection, sites) => connection.WriteBlockingSites(sites)),
        DevicePart(records => records.CustomFilterLists, (now, was) => now.SequenceEqual(was),
            (connection, lists) => connection.WriteCustomFilterLists(lists)),
        DevicePart(records => records.CustomFilters, (now, was) => now == was, (connection, text) => connection.WriteCustomFilters(text)),
    ];

    #endregion

    #region Actions - Device store

    /// Creates the device store's tables beside the checkpoint table. They are
    /// additive: a build that predates them reads the file as before.
    /// `device_marker` holds the adoptions an older build knows, which it
    /// rewrites; `device_adoption` holds every adoption, and no older build
    /// touches it.
    public void CreateDeviceTables() {
        Execute("CREATE TABLE IF NOT EXISTS device_window (id TEXT PRIMARY KEY, shown_space TEXT NOT NULL, used INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_window_tab (window TEXT NOT NULL, space TEXT NOT NULL, tab TEXT, "
            + "PRIMARY KEY (window, space))");
        Execute("CREATE TABLE IF NOT EXISTS device_window_split (window TEXT NOT NULL, split_group TEXT NOT NULL, "
            + "position INTEGER NOT NULL, share REAL NOT NULL, PRIMARY KEY (window, split_group, position))");
        Execute("CREATE TABLE IF NOT EXISTS device_window_reopen (id TEXT PRIMARY KEY, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_marker (name TEXT PRIMARY KEY)");
        Execute("CREATE TABLE IF NOT EXISTS device_adoption (name TEXT PRIMARY KEY)");
        Execute("CREATE TABLE IF NOT EXISTS device_site_permission (id TEXT PRIMARY KEY, space TEXT NOT NULL, scheme TEXT NOT NULL, "
            + "host TEXT NOT NULL, port INTEGER NOT NULL, permission TEXT NOT NULL, detail TEXT, decision TEXT NOT NULL, "
            + "modified_at REAL NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_site_engine (scheme TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL, "
            + "engine TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (scheme, host, port))");
        Execute("CREATE TABLE IF NOT EXISTS device_engine (id INTEGER PRIMARY KEY CHECK (id = 0), engine TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_shortcut (command TEXT PRIMARY KEY, key TEXT, special INTEGER NOT NULL, "
            + "modifiers INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_shortcut_preference (command TEXT PRIMARY KEY, preference TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link (id INTEGER PRIMARY KEY CHECK (id = 0), destination TEXT NOT NULL, "
            + "destination_space TEXT, peek_modifier TEXT NOT NULL, archive_policy TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link_behavior (name TEXT PRIMARY KEY, is_on INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link_route (id TEXT PRIMARY KEY, enabled INTEGER NOT NULL, match TEXT NOT NULL, "
            + "pattern TEXT NOT NULL, space TEXT NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link_site (site TEXT PRIMARY KEY, space TEXT NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_cloud_transport (id INTEGER PRIMARY KEY CHECK (id = 0), "
            + "record_schema INTEGER NOT NULL, requires_full_pull INTEGER NOT NULL, awaits_account_decision INTEGER NOT NULL, "
            + "overwrites_cloud INTEGER NOT NULL, engine_state BLOB)");
        Execute("CREATE TABLE IF NOT EXISTS device_cloud_record (name TEXT PRIMARY KEY, fields BLOB NOT NULL, schema_version INTEGER)");
        Execute("CREATE TABLE IF NOT EXISTS device_setup_draft (id INTEGER PRIMARY KEY CHECK (id = 0), document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_palette (space TEXT PRIMARY KEY, document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_search_catalog (id INTEGER PRIMARY KEY CHECK (id = 0), document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_download (id TEXT PRIMARY KEY, profile TEXT NOT NULL, created INTEGER NOT NULL, "
            + "document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_import_outcome (id TEXT PRIMARY KEY, document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_setup (id INTEGER PRIMARY KEY CHECK (id = 0), completed INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_tab_group (id TEXT PRIMARY KEY, space TEXT NOT NULL, engine TEXT NOT NULL, "
            + "title TEXT NOT NULL, color TEXT NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_agents (id INTEGER PRIMARY KEY CHECK (id = 0), is_on INTEGER NOT NULL, "
            + "runs_scripts INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_agents_space (id INTEGER PRIMARY KEY CHECK (id = 0), space TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_agent_space (space TEXT PRIMARY KEY, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_agent (position INTEGER PRIMARY KEY, team TEXT, signing TEXT, path TEXT, "
            + "client TEXT, name TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_filter_list (name TEXT PRIMARY KEY, is_on INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_blocking_site (space TEXT NOT NULL, scheme TEXT NOT NULL, host TEXT NOT NULL, "
            + "port INTEGER NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (space, scheme, host, port))");
        Execute("CREATE TABLE IF NOT EXISTS device_custom_filter_list (id TEXT PRIMARY KEY, url TEXT NOT NULL, is_on INTEGER NOT NULL, "
            + "position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_custom_filters (id INTEGER PRIMARY KEY CHECK (id = 0), text TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_content_blocking (id INTEGER PRIMARY KEY CHECK (id = 0), level TEXT NOT NULL)");
    }

    /// Everything the device store holds. A row whose identities or names do
    /// not read is left out.
    public DeviceRecords ReadDevice() => new(ReadWindows(), ReadReopening(), ReadSitePermissions(), ReadSiteEngines(), ReadShortcuts(),
        ReadLinks(), ReadSetupDraft(), ReadSetupCompleted(), ReadAdoptions(), ReadTabGroups(), ReadDefaultEngine()) {
        PaletteMemories = ReadPaletteMemories(),
        SearchCatalog = ReadSearchCatalog(),
        Agents = ReadAgents(),
        Downloads = ReadDownloads(),
        ImportOutcomes = ReadImportOutcomes(),
        ContentBlockingLevel = ReadContentBlockingLevel(),
        FilterListChoices = ReadFilterListChoices(),
        BlockingSites = ReadBlockingSites(),
        CustomFilterLists = ReadCustomFilterLists(),
        CustomFilters = ReadCustomFilters()
    };

    private List<SetupImportOutcome> ReadImportOutcomes() {
        var outcomes = new List<SetupImportOutcome>();
        Rows("SELECT document FROM device_import_outcome ORDER BY rowid", statement => {
            if (SetupImportOutcomeDocument.Read(statement.Text(0)) is { } outcome) outcomes.Add(outcome);
        });
        return outcomes;
    }

    /// The ended downloads the store keeps that read, newest first.
    private List<DownloadState> ReadDownloads() {
        var downloads = new List<DownloadState>();
        Rows("SELECT id, profile, created, document FROM device_download ORDER BY created DESC, id", statement => {
            if (Identity(statement, 0) is not { } id || Identity(statement, 1) is not { } profile) return;
            var created = DateTimeOffset.FromUnixTimeMilliseconds(statement.Long(2));
            if (KeptDownloadDocument.Read(id, profile, created, statement.Text(3)) is { } download)
                downloads.Add(download);
        });
        return downloads;
    }

    /// The lists the person turned on or off. A list this build does not know
    /// is left out.
    /// The level ad blocking blocks at, or null for none kept or a level this
    /// build does not know.
    private ContentBlockingLevel? ReadContentBlockingLevel() {
        ContentBlockingLevel? level = null;
        Rows("SELECT level FROM device_content_blocking", statement =>
            level = ContentBlockingLevel.Named(statement.Text(0)));
        return level;
    }

    private Dictionary<FilterList, bool> ReadFilterListChoices() {
        var choices = new Dictionary<FilterList, bool>();
        Rows("SELECT name, is_on FROM device_filter_list", statement => {
            if (FilterList.Named(statement.Text(0)) is { } list) choices[list] = statement.Int(1) != 0;
        });
        return choices;
    }

    /// The sites where Spaces block nothing, in the order they were added. A
    /// row whose Space or origin does not read is left out.
    private List<SiteContentBlocking> ReadBlockingSites() {
        var sites = new List<SiteContentBlocking>();
        Rows("SELECT space, scheme, host, port FROM device_blocking_site ORDER BY position", statement => {
            if (Identity(statement, 0) is not { } space) return;
            var origin = new SiteOrigin(statement.Text(1), statement.Text(2),
                statement.Int(3));
            if (origin.IsValid) sites.Add(new(space, origin));
        });
        return sites;
    }

    /// The filter lists the person added, in order. A row whose identity does
    /// not read is left out.
    private List<CustomFilterList> ReadCustomFilterLists() {
        var lists = new List<CustomFilterList>();
        Rows("SELECT id, url, is_on FROM device_custom_filter_list ORDER BY position", statement => {
            if (Identity(statement, 0) is { } id)
                lists.Add(new(id, statement.Text(1), statement.Int(2) != 0));
        });
        return lists;
    }

    /// The person's own filters, or none.
    private string ReadCustomFilters() {
        string text = "";
        Rows("SELECT text FROM device_custom_filters", statement => text = statement.Text(0));
        return text;
    }

    /// The search catalog the store keeps, or null when it keeps none or it does not read.
    private SearchCatalog? ReadSearchCatalog() {
        string? document = null;
        Rows("SELECT document FROM device_search_catalog", statement => document = statement.Text(0));
        return SearchCatalogDocument.Read(document);
    }

    /// Each persistent Space's palette memory that reads, by Space.
    private Dictionary<Guid, PaletteMemory> ReadPaletteMemories() {
        var memories = new Dictionary<Guid, PaletteMemory>();
        Rows("SELECT space, document FROM device_palette", statement => {
            if (Identity(statement, 0) is { } space && PaletteMemoryDocument.Read(statement.Text(1)) is { } memory)
                memories[space] = memory;
        });
        return memories;
    }

    /// The person's preference remains available even in a single-engine product.
    private EngineKind? ReadDefaultEngine() {
        EngineKind? engine = null;
        Rows("SELECT engine FROM device_engine WHERE id = 0", statement => engine = EngineKind.Named(statement.Text(0)));
        return engine;
    }

    private List<SavedWindow> ReadWindows() {
        var windows = new Dictionary<Guid, (Guid ShownSpace, long Used)>();
        var tabs = new List<(Guid Window, ShownTab Tab)>();
        var shares = new List<(Guid Window, Guid Group, double Share)>();
        Rows("SELECT id, shown_space, used FROM device_window", statement => {
            if (Identity(statement, 0) is { } id && Identity(statement, 1) is { } shown)
                windows[id] = (shown, statement.Long(2));
        });
        Rows("SELECT window, space, tab FROM device_window_tab", statement => {
            if (Identity(statement, 0) is { } window && Identity(statement, 1) is { } space)
                tabs.Add((window, new ShownTab(space, statement.IsNull(2) ? null : Identity(statement, 2))));
        });
        Rows("SELECT window, split_group, share FROM device_window_split ORDER BY window, split_group, position", statement => {
            if (Identity(statement, 0) is { } window && Identity(statement, 1) is { } group)
                shares.Add((window, group, statement.Double(2)));
        });
        return [.. windows.Select(window => new SavedWindow(window.Key, window.Value.ShownSpace,
            [.. tabs.Where(tab => tab.Window == window.Key).Select(tab => tab.Tab)],
            [.. shares.Where(share => share.Window == window.Key).GroupBy(share => share.Group)
                .Select(group => new SplitColumnShares(group.Key, [.. group.Select(share => share.Share)]))],
            window.Value.Used)).OrderBy(record => record.Used)];
    }

    /// The saved windows the next launch reopens, back to front.
    private List<Guid> ReadReopening() {
        var windows = new List<Guid>();
        Rows("SELECT id FROM device_window_reopen ORDER BY position", statement => {
            if (Identity(statement, 0) is { } id) windows.Add(id);
        });
        return windows;
    }

    private List<SitePermissionRecord> ReadSitePermissions() {
        var records = new List<SitePermissionRecord>();
        Rows("SELECT id, space, scheme, host, port, permission, detail, decision, modified_at FROM device_site_permission "
            + "ORDER BY position", statement => {
                if (Identity(statement, 0) is not { } id || Identity(statement, 1) is not { } space
                    || SitePermission.Named(statement.Text(5)) is not { } permission
                    || SitePermissionDecision.Named(statement.Text(7)) is not { } decision) return;
                records.Add(new(id, space,
                    new SiteOrigin(statement.Text(2), statement.Text(3), statement.Int(4)),
                    permission, statement.IsNull(6) ? null : statement.Text(6), decision,
                    statement.Double(8)));
            });
        return records;
    }

    /// The tab groups whose folders follow them, in storage order. A group a
    /// later release names by an engine or color this one cannot read is left
    /// out.
    private List<TabGroupRecord> ReadTabGroups() {
        var groups = new List<TabGroupRecord>();
        Rows("SELECT id, space, engine, title, color FROM device_tab_group ORDER BY position", statement => {
            if (Identity(statement, 0) is { } id && Identity(statement, 1) is { } space
                && EngineKind.Named(statement.Text(2)) is { } engine
                && TabGroupColor.Named(statement.Text(4)) is { } color)
                groups.Add(new(id, space, engine, statement.Text(3), color));
        });
        return groups;
    }

    /// The site engine choices, least recent first. A row naming an engine
    /// this build does not know is left out.
    private List<SiteEngineChoice> ReadSiteEngines() {
        var choices = new List<SiteEngineChoice>();
        Rows("SELECT scheme, host, port, engine FROM device_site_engine ORDER BY position", statement => {
            if (EngineKind.Named(statement.Text(3)) is not { } engine) return;
            var origin = new SiteOrigin(statement.Text(0), statement.Text(1),
                statement.Int(2));
            if (origin.IsValid) choices.Add(new(null, origin, engine));
        });
        return choices;
    }

    /// Each command's choices: no key is a command left without one, and a
    /// preference this build does not know is left out.
    private ShortcutOverrides ReadShortcuts() {
        var choices = new List<KeyValuePair<string, ShortcutChord?>>();
        Rows("SELECT command, key, special, modifiers FROM device_shortcut ORDER BY command", statement => {
            string command = statement.Text(0);
            if (statement.IsNull(1)) {
                choices.Add(new(command, null));
                return;
            }
            string key = statement.Text(1);
            int modifiers = statement.Int(3);
            bool special = statement.Int(2) != 0;
            if (special ? ShortcutSpecialKey.Named(key) is null : key.Length is 0 or > ShortcutChord.MaximumCharacterLength) return;
            choices.Add(new(command, special ? ShortcutChord.Special(key, modifiers) : ShortcutChord.Character(key, modifiers)));
        });
        var preferences = new List<KeyValuePair<string, ShortcutPreference>>();
        Rows("SELECT command, preference FROM device_shortcut_preference ORDER BY command", statement => {
            if (ShortcutPreference.Named(statement.Text(1)) is { } preference)
                preferences.Add(new(statement.Text(0), preference));
        });
        return ShortcutOverrides.Restore(choices, preferences);
    }

    /// The link preferences, each value that does not read keeping its
    /// default: a device that never chose any holds no rows.
    private LinkPreferences ReadLinks() {
        var links = LinkPreferences.Default;
        Rows("SELECT destination, destination_space, peek_modifier, archive_policy FROM device_link", statement => links = links with {
            Destination = ExternalLinkDestination.Named(statement.Text(0)) ?? links.Destination,
            DestinationSpaceId = Identity(statement, 1),
            PeekModifier = LinkPeekModifier.Named(statement.Text(2)) ?? links.PeekModifier,
            ArchivePolicy = QuickWindowArchivePolicy.Named(statement.Text(3)) ?? links.ArchivePolicy
        });
        Rows("SELECT name, is_on FROM device_link_behavior", statement => {
            if (LinkBehavior.Named(statement.Text(0)) is { } behavior)
                links = behavior.Setting(links, statement.Int(1) != 0);
        });
        var routes = new List<LinkRoute>();
        Rows("SELECT id, enabled, match, pattern, space FROM device_link_route ORDER BY position", statement => {
            if (Identity(statement, 0) is { } id && LinkRouteMatch.Named(statement.Text(2)) is { } match
                && Identity(statement, 4) is { } space)
                routes.Add(new(id, statement.Int(1) != 0, match, statement.Text(3), space));
        });
        var sites = new List<RememberedSite>();
        Rows("SELECT site, space FROM device_link_site ORDER BY position", statement => {
            if (Identity(statement, 1) is { } space) sites.Add(new(statement.Text(0), space));
        });
        return links with { Routes = routes, RememberedSites = sites };
    }

    /// The agent preferences: off, reaching nothing and trusting no agent for a
    /// device that never chose any, and with no Space of agents' own for one
    /// that never made it. A Space or agent that does not read is left out.
    private AgentPreferences ReadAgents() {
        bool isOn = false;
        bool runsScripts = false;
        Rows("SELECT is_on, runs_scripts FROM device_agents", statement => {
            isOn = statement.Int(0) != 0;
            runsScripts = statement.Int(1) != 0;
        });
        var spaces = new List<Guid>();
        Rows("SELECT space FROM device_agent_space ORDER BY position", statement => {
            if (Identity(statement, 0) is { } space) spaces.Add(space);
        });
        var approved = new List<ApprovedAgent>();
        static string? Optional(SqliteStatement statement, int column) => statement.IsNull(column) ? null : statement.Text(column);
        Rows("SELECT team, signing, path, client, name FROM device_agent ORDER BY position", statement => {
            var identity = new AgentIdentity(Optional(statement, 0), Optional(statement, 1), Optional(statement, 2),
                Optional(statement, 3));
            if (identity.IsValid && AgentPreferences.CleanName(statement.Text(4)) is { } name)
                approved.Add(new ApprovedAgent(identity, name));
        });
        Guid? agentsSpace = null;
        Rows("SELECT space FROM device_agents_space", statement => agentsSpace = Identity(statement, 0));
        return new(isOn, runsScripts, spaces, approved) { AgentsSpaceId = agentsSpace };
    }

    /// The unfinished manual setup, or null when the store keeps none or it
    /// does not read.
    private KeptSetupDraft? ReadSetupDraft() {
        string? document = null;
        Rows("SELECT document FROM device_setup_draft", statement => document = statement.Text(0));
        return KeptSetupDraft.Read(document);
    }

    /// Whether this device has completed setup: never, until the store says so.
    private bool ReadSetupCompleted() {
        bool completed = false;
        Rows("SELECT completed FROM device_setup", statement => completed = statement.Int(0) != 0);
        return completed;
    }

    private HashSet<DeviceAdoption> ReadAdoptions() {
        var adoptions = new HashSet<DeviceAdoption>();
        foreach (var table in new[] { "device_marker", "device_adoption" })
            Rows($"SELECT name FROM {table}", statement => {
                if (DeviceAdoption.Marked(statement.Text(0)) is { } adoption) adoptions.Add(adoption);
            });
        return adoptions;
    }

    /// Writes `records` over what the device store holds, rewriting only the
    /// parts that differ from `written`, which the store holds now; with null,
    /// every part. The caller runs it inside a transaction.
    public void WriteDevice(DeviceRecords records, DeviceRecords? written) {
        foreach (var write in DeviceParts) write(this, records, written);
    }

    /// Writes one part of the device store: its `part` of the records when
    /// nothing was written yet or it is not the `same` as what was.
    private static DevicePartWrite DevicePart<T>(Func<DeviceRecords, T> part, Func<T, T, bool> same,
        Action<SqliteConnection, T> write) => (connection, records, written) => {
            if (written is null || !same(part(records), part(written))) write(connection, part(records));
        };

    /// Each import outcome `written` lacks, carrying the document the store
    /// already keeps for its import.
    private void WriteImportOutcomes(IReadOnlyList<SetupImportOutcome> outcomes, IReadOnlyList<SetupImportOutcome>? written) {
        foreach (var outcome in outcomes) {
            if (written?.Contains(outcome) == true) continue;
            string? previousDocument;
            using (var previous = Prepare("SELECT document FROM device_import_outcome WHERE id = ?"))
                previousDocument = previous.Bind(1, Spelling(outcome.Id)).First<string?>(row => row.Text(0), null);
            Insert("INSERT INTO device_import_outcome(id, document) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET document = excluded.document", statement => {
                statement.Bind(1, Spelling(outcome.Id));
                statement.Bind(2, SetupImportOutcomeDocument.Write(outcome, previousDocument));
            });
        }
    }

    /// Each kept download that differs from what was written, and no row for
    /// one no longer kept.
    private void WriteDownloads(IReadOnlyList<DownloadState> downloads, IReadOnlyList<DownloadState>? written) {
        if (written is not null && downloads.SequenceEqual(written)) return;
        var kept = written?.ToDictionary(download => download.Id) ?? [];
        if (written is null) Execute("DELETE FROM device_download");
        var current = downloads.Select(download => download.Id).ToHashSet();
        foreach (var gone in kept.Keys.Where(id => !current.Contains(id)))
            Insert("DELETE FROM device_download WHERE id = ?", statement => statement.Bind(1, Spelling(gone)));
        foreach (var download in downloads) {
            if (kept.TryGetValue(download.Id, out var same) && same == download) continue;
            Insert("INSERT OR REPLACE INTO device_download(id, profile, created, document) VALUES(?,?,?,?)", statement => {
                statement.Bind(1, Spelling(download.Id));
                statement.Bind(2, Spelling(download.ProfileId));
                statement.Bind(3, download.CreatedAt.ToUnixTimeMilliseconds());
                statement.Bind(4, KeptDownloadDocument.Write(download));
            });
        }
    }

    /// The search catalog as its one document, or no row before it was first restored.
    private void WriteSearchCatalog(SearchCatalog? catalog) {
        Execute("DELETE FROM device_search_catalog");
        if (catalog is null) return;
        Insert("INSERT INTO device_search_catalog(id, document) VALUES(0,?)",
            statement => statement.Bind(1, SearchCatalogDocument.Write(catalog)));
    }

    /// Each Space's palette memory that differs from what was written, and no
    /// row for a Space whose memory went.
    private void WritePaletteMemories(IReadOnlyDictionary<Guid, PaletteMemory> memories, IReadOnlyDictionary<Guid, PaletteMemory>? written) {
        if (written is null) Execute("DELETE FROM device_palette");
        foreach (var gone in written?.Keys.Where(space => !memories.ContainsKey(space)) ?? [])
            Insert("DELETE FROM device_palette WHERE space = ?", statement => statement.Bind(1, Spelling(gone)));
        foreach (var (space, memory) in memories) {
            if (written is not null && written.TryGetValue(space, out var kept) && ReferenceEquals(kept, memory)) continue;
            Insert("INSERT OR REPLACE INTO device_palette(space, document) VALUES(?,?)", statement => {
                statement.Bind(1, Spelling(space));
                statement.Bind(2, PaletteMemoryDocument.Write(memory));
            });
        }
    }

    /// The agent preferences: whether they are on and run scripts in pages,
    /// the Space of agents' own, and the allowed Spaces and approved agents in
    /// order.
    private void WriteAgents(AgentPreferences preferences) {
        foreach (var table in new[] { "device_agents", "device_agents_space", "device_agent_space", "device_agent" })
            Execute($"DELETE FROM {table}");
        Insert("INSERT INTO device_agents(id, is_on, runs_scripts) VALUES(0,?,?)", statement => {
            statement.Bind(1, preferences.IsOn ? 1 : 0);
            statement.Bind(2, preferences.RunsScripts ? 1 : 0);
        });
        if (preferences.AgentsSpaceId is { } agentsSpace)
            Insert("INSERT INTO device_agents_space(id, space) VALUES(0,?)", statement => statement.Bind(1, Spelling(agentsSpace)));
        InsertInOrder("INSERT INTO device_agent_space(space, position) VALUES(?,?)", preferences.SpaceIds, (statement, space, index) => {
            statement.Bind(1, Spelling(space));
            statement.Bind(2, index);
        });
        InsertInOrder("INSERT INTO device_agent(position, team, signing, path, client, name) VALUES(?,?,?,?,?,?)",
            preferences.Agents, (statement, agent, index) => {
                statement.Bind(1, index);
                statement.Bind(2, agent.Identity.TeamId);
                statement.Bind(3, agent.Identity.SigningId);
                statement.Bind(4, agent.Identity.Path);
                statement.Bind(5, agent.Identity.Client);
                statement.Bind(6, agent.Name);
            });
    }

    /// The tab groups in order, each engine and color by its `Name`.
    private void WriteTabGroups(IReadOnlyList<TabGroupRecord> groups) {
        Execute("DELETE FROM device_tab_group");
        InsertInOrder("INSERT INTO device_tab_group(id, space, engine, title, color, position) VALUES(?,?,?,?,?,?)",
            groups, (statement, group, index) => {
                statement.Bind(1, Spelling(group.Id));
                statement.Bind(2, Spelling(group.SpaceId));
                statement.Bind(3, group.Engine.Name);
                statement.Bind(4, group.Title);
                statement.Bind(5, group.Color.Name);
                statement.Bind(6, index);
            });
    }

    private void WriteWindows(IReadOnlyList<SavedWindow> windows) {
        foreach (var table in new[] { "device_window", "device_window_tab", "device_window_split" }) Execute($"DELETE FROM {table}");
        foreach (var window in windows) {
            Insert("INSERT INTO device_window(id, shown_space, used) VALUES(?,?,?)", statement => {
                statement.Bind(1, Spelling(window.Id));
                statement.Bind(2, Spelling(window.ShownSpaceId));
                statement.Bind(3, window.Used);
            });
            foreach (var tab in window.Tabs)
                Insert("INSERT INTO device_window_tab(window, space, tab) VALUES(?,?,?)", statement => {
                    statement.Bind(1, Spelling(window.Id));
                    statement.Bind(2, Spelling(tab.SpaceId));
                    statement.Bind(3, tab.TabId is { } id ? Spelling(id) : null);
                });
            foreach (var group in window.Shares)
                for (int position = 0; position < group.Shares.Count; position++) {
                    int column = position;
                    Insert("INSERT INTO device_window_split(window, split_group, position, share) VALUES(?,?,?,?)", statement => {
                        statement.Bind(1, Spelling(window.Id));
                        statement.Bind(2, Spelling(group.GroupId));
                        statement.Bind(3, column);
                        statement.Bind(4, group.Shares[column]);
                    });
                }
        }
    }

    /// The saved windows the next launch reopens, in order, back to front.
    private void WriteReopening(IReadOnlyList<Guid> windows) {
        Execute("DELETE FROM device_window_reopen");
        InsertInOrder("INSERT INTO device_window_reopen(id, position) VALUES(?,?)", windows, (statement, window, index) => {
            statement.Bind(1, Spelling(window));
            statement.Bind(2, index);
        });
    }

    /// The choices in storage order, with every value exactly as the record
    /// holds it: the capability and decision by `Name`, the time as the double
    /// it was.
    private void WriteSitePermissions(IReadOnlyList<SitePermissionRecord> records) {
        Execute("DELETE FROM device_site_permission");
        InsertInOrder("INSERT INTO device_site_permission(id, space, scheme, host, port, permission, detail, decision, modified_at, position) "
            + "VALUES(?,?,?,?,?,?,?,?,?,?)",
            records, (statement, record, index) => {
                statement.Bind(1, Spelling(record.Id));
                statement.Bind(2, Spelling(record.Space));
                statement.Bind(3, record.Origin.Scheme);
                statement.Bind(4, record.Origin.Host);
                statement.Bind(5, record.Origin.Port);
                statement.Bind(6, record.Permission.Name);
                statement.Bind(7, record.Detail);
                statement.Bind(8, record.Decision.Name);
                statement.Bind(9, record.ModifiedAt);
                statement.Bind(10, index);
            });
    }

    /// The person's explicit default, absent while following the composition.
    private void WriteDefaultEngine(EngineKind? engine) {
        Execute("DELETE FROM device_engine");
        if (engine is not null)
            Insert("INSERT INTO device_engine(id, engine) VALUES(0,?)", statement => statement.Bind(1, engine.Name));
    }

    /// The site engine choices, least recent first, each engine by `Name`.
    private void WriteSiteEngines(IReadOnlyList<SiteEngineChoice> choices) {
        Execute("DELETE FROM device_site_engine");
        InsertInOrder("INSERT INTO device_site_engine(scheme, host, port, engine, position) VALUES(?,?,?,?,?)",
            choices, (statement, choice, index) => {
                statement.Bind(1, choice.Origin.Scheme);
                statement.Bind(2, choice.Origin.Host);
                statement.Bind(3, choice.Origin.Port);
                statement.Bind(4, choice.Engine.Name);
                statement.Bind(5, index);
            });
    }

    /// Each command's choices, with the modifier mask's every bit; a command
    /// left without a chord has no key, and a preference is kept by its name.
    private void WriteShortcuts(ShortcutOverrides shortcuts) {
        Execute("DELETE FROM device_shortcut");
        Execute("DELETE FROM device_shortcut_preference");
        foreach (var (command, preference) in shortcuts.Preferences)
            Insert("INSERT INTO device_shortcut_preference(command, preference) VALUES(?,?)", statement => {
                statement.Bind(1, command);
                statement.Bind(2, preference.Name);
            });
        foreach (var (command, chord) in shortcuts.Chords)
            Insert("INSERT INTO device_shortcut(command, key, special, modifiers) VALUES(?,?,?,?)", statement => {
                statement.Bind(1, command);
                statement.Bind(2, chord?.Key);
                statement.Bind(3, chord?.IsSpecial == true ? 1 : 0);
                statement.Bind(4, chord?.Modifiers ?? 0);
            });
    }

    /// The link preferences: the fixed sets by `Name`, each on-or-off
    /// preference under its behavior's `Name`, and the routes and remembered
    /// sites in order.
    private void WriteLinks(LinkPreferences links) {
        foreach (var table in new[] { "device_link", "device_link_behavior", "device_link_route", "device_link_site" })
            Execute($"DELETE FROM {table}");
        Insert("INSERT INTO device_link(id, destination, destination_space, peek_modifier, archive_policy) VALUES(0,?,?,?,?)", statement => {
            statement.Bind(1, links.Destination.Name);
            statement.Bind(2, links.DestinationSpaceId is { } space ? Spelling(space) : null);
            statement.Bind(3, links.PeekModifier.Name);
            statement.Bind(4, links.ArchivePolicy.Name);
        });
        foreach (var behavior in LinkBehavior.All)
            Insert("INSERT INTO device_link_behavior(name, is_on) VALUES(?,?)", statement => {
                statement.Bind(1, behavior.Name);
                statement.Bind(2, behavior.IsOn(links) ? 1 : 0);
            });
        InsertInOrder("INSERT INTO device_link_route(id, enabled, match, pattern, space, position) VALUES(?,?,?,?,?,?)",
            links.Routes, (statement, route, index) => {
                statement.Bind(1, Spelling(route.Id));
                statement.Bind(2, route.IsEnabled ? 1 : 0);
                statement.Bind(3, route.Match.Name);
                statement.Bind(4, route.Pattern);
                statement.Bind(5, Spelling(route.DestinationSpaceId));
                statement.Bind(6, index);
            });
        InsertInOrder("INSERT INTO device_link_site(site, space, position) VALUES(?,?,?)",
            links.RememberedSites, (statement, remembered, index) => {
                statement.Bind(1, remembered.Site);
                statement.Bind(2, Spelling(remembered.SpaceId));
                statement.Bind(3, index);
            });
    }

    /// The unfinished manual setup as its one document, or no row for none.
    private void WriteSetupDraft(KeptSetupDraft? draft) {
        Execute("DELETE FROM device_setup_draft");
        if (draft is null) return;
        Insert("INSERT INTO device_setup_draft(id, document) VALUES(0,?)", statement => statement.Bind(1, draft.Document));
    }

    private static bool SameChoices(IReadOnlyDictionary<FilterList, bool> choices, IReadOnlyDictionary<FilterList, bool> written) =>
        choices.Count == written.Count && choices.All(entry => written.TryGetValue(entry.Key, out bool isOn) && isOn == entry.Value);

    private void WriteContentBlockingLevel(ContentBlockingLevel? level) {
        Execute("DELETE FROM device_content_blocking");
        if (level is null) return;
        Insert("INSERT INTO device_content_blocking(id, level) VALUES(0,?)", statement => statement.Bind(1, level.Name));
    }

    private void WriteFilterListChoices(IReadOnlyDictionary<FilterList, bool> choices) {
        Execute("DELETE FROM device_filter_list");
        foreach (var (list, isOn) in choices)
            Insert("INSERT INTO device_filter_list(name, is_on) VALUES(?,?)", statement => {
                statement.Bind(1, list.Name);
                statement.Bind(2, isOn ? 1 : 0);
            });
    }

    private void WriteBlockingSites(IReadOnlyList<SiteContentBlocking> sites) {
        Execute("DELETE FROM device_blocking_site");
        InsertInOrder("INSERT INTO device_blocking_site(space, scheme, host, port, position) VALUES(?,?,?,?,?)",
            sites, (statement, site, index) => {
                statement.Bind(1, Spelling(site.SpaceId));
                statement.Bind(2, site.Origin.Scheme);
                statement.Bind(3, site.Origin.Host);
                statement.Bind(4, site.Origin.Port);
                statement.Bind(5, index);
            });
    }

    private void WriteCustomFilterLists(IReadOnlyList<CustomFilterList> lists) {
        Execute("DELETE FROM device_custom_filter_list");
        InsertInOrder("INSERT INTO device_custom_filter_list(id, url, is_on, position) VALUES(?,?,?,?)",
            lists, (statement, list, index) => {
                statement.Bind(1, Spelling(list.Id));
                statement.Bind(2, list.Url);
                statement.Bind(3, list.IsOn ? 1 : 0);
                statement.Bind(4, index);
            });
    }

    private void WriteCustomFilters(string text) {
        Execute("DELETE FROM device_custom_filters");
        if (text.Length == 0) return;
        Insert("INSERT INTO device_custom_filters(id, text) VALUES(0,?)", statement => statement.Bind(1, text));
    }

    private void WriteSetupCompleted(bool completed) {
        Execute("DELETE FROM device_setup");
        Insert("INSERT INTO device_setup(id, completed) VALUES(0,?)", statement => statement.Bind(1, completed ? 1 : 0));
    }

    /// Every adoption goes into `device_adoption`; the ones an older build
    /// knows also go into `device_marker`, which that build reads and rewrites.
    /// An adoption is never undone, so the markers are only ever added: a
    /// write of records captured before an adoption another save recorded
    /// keeps its marker.
    private void WriteAdoptions(IReadOnlySet<DeviceAdoption> adoptions) {
        foreach (var adoption in DeviceAdoption.All.Where(adoptions.Contains)) MarkAdopted(adoption);
    }

    /// Records `adoption` as done. The caller runs it inside a transaction.
    public void MarkAdopted(DeviceAdoption adoption) {
        Insert("INSERT OR IGNORE INTO device_adoption(name) VALUES(?)", statement => statement.Bind(1, adoption.Marker));
        if (adoption.OlderBuildsRead)
            Insert("INSERT OR IGNORE INTO device_marker(name) VALUES(?)", statement => statement.Bind(1, adoption.Marker));
    }

    #endregion

    #region Actions - Cloud transport

    /// The cloud transport's state the device store keeps, or null while it
    /// keeps none.
    public CloudTransportRecord? ReadCloudTransport() {
        using var statement = Prepare(
            "SELECT record_schema, requires_full_pull, awaits_account_decision, overwrites_cloud, engine_state FROM device_cloud_transport");
        return statement.First<CloudTransportRecord?>(row => new CloudTransportRecord(checked((int)row.Long(0)), row.Long(1) != 0,
            row.Long(2) != 0, row.Long(3) != 0, row.IsNull(4) ? null : row.Blob(4)), null);
    }

    /// Writes `record` over the cloud transport's state. The caller runs it
    /// inside a transaction.
    public void WriteCloudTransport(CloudTransportRecord record) {
        Execute("DELETE FROM device_cloud_transport");
        Insert("INSERT INTO device_cloud_transport(id, record_schema, requires_full_pull, awaits_account_decision, overwrites_cloud, "
            + "engine_state) VALUES(0,?,?,?,?,?)", statement => {
                statement.Bind(1, record.RecordSchema);
                statement.Bind(2, record.RequiresFullPull ? 1 : 0);
                statement.Bind(3, record.AwaitsAccountDecision ? 1 : 0);
                statement.Bind(4, record.OverwritesCloud ? 1 : 0);
                if (record.EngineState is { } state) statement.Bind(5, state);
                else statement.BindNull(5);
            });
    }

    /// Forgets every record's server fields when `clearing`, then keeps those
    /// of `updated` and forgets those of `removed`. The caller runs it inside
    /// a transaction.
    public void WriteCloudFields(bool clearing, IReadOnlyList<CloudRecordFields> updated, IReadOnlyList<string> removed) {
        if (clearing) Execute("DELETE FROM device_cloud_record");
        foreach (var name in removed)
            Insert("DELETE FROM device_cloud_record WHERE name=?", statement => statement.Bind(1, name));
        foreach (var fields in updated)
            Insert("INSERT OR REPLACE INTO device_cloud_record(name, fields, schema_version) VALUES(?,?,?)", statement => {
                statement.Bind(1, fields.RecordName);
                statement.Bind(2, fields.Fields);
                if (fields.SchemaVersion is { } schema) statement.Bind(3, schema);
                else statement.BindNull(3);
            });
    }

    /// The server fields kept of `names`; a record kept without any is left
    /// out.
    public IReadOnlyList<CloudRecordFields> ReadCloudFields(IReadOnlyList<string> names) {
        var found = new List<CloudRecordFields>();
        foreach (var name in names) {
            using var statement = Prepare("SELECT fields, schema_version FROM device_cloud_record WHERE name=?");
            if (statement.Bind(1, name).First<CloudRecordFields?>(row => new(name, row.Blob(0),
                row.IsNull(1) ? null : checked((int)row.Long(1))), null) is { } kept) found.Add(kept);
        }
        return found;
    }

    /// Runs `sql` once and hands `row` each row it answers, in order.
    private void Rows(string sql, Action<SqliteStatement> row) {
        using var statement = Prepare(sql);
        statement.Rows(row);
    }

    /// Inserts one row per item of `items` with `sql`, each bound by `bind`
    /// with the item and its position in the list.
    private void InsertInOrder<T>(string sql, IReadOnlyList<T> items, Action<SqliteStatement, T, int> bind) {
        if (items.Count == 0) return;
        using var statement = Prepare(sql);
        for (int position = 0; position < items.Count; position++) {
            bind(statement, items[position], position);
            statement.Run();
        }
    }

    /// Runs `sql` once with the values `bind` binds.
    private void Insert(string sql, Action<SqliteStatement> bind) {
        using var statement = Prepare(sql);
        bind(statement);
        statement.Run();
    }

    private static Guid? Identity(SqliteStatement statement, int column) =>
        Guid.TryParse(statement.Text(column), out var id) ? id : null;

    /// An identity as the store spells it.
    private static string Spelling(Guid id) => id.ToString("D").ToUpperInvariant();

    #endregion
}
