using System.Text;
using System.Text.Json;

using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

/// How Ode reads each browser it imports from: where in its data folder it
/// keeps each profile's bookmarks, latest session and saved passwords, and
/// the readers for those files. A browser's `Source` is what the platform and
/// the person see of it.
internal sealed partial class InstalledBrowser {
    #region Static Variables

    public static readonly InstalledBrowser Arc = new(ImportSource.Arc, ArcProfiles, folder => ChromiumPasswordStores(folder.Child("User Data")),
        ArcSidebar.Read, bookmarks: null, chromium: true, extensions: true,
        completes: (path, drafts, room, importedAt, problems) =>
            ArcSidebar.Completed(Path.GetDirectoryName(path) ?? path, drafts, room, importedAt, problems));
    public static readonly InstalledBrowser Zen = new(ImportSource.Zen, ZenProfiles, _ => [], ZenSessions.Read, bookmarks: null,
        history: MozillaPlaces.History);
    public static readonly InstalledBrowser Chrome = new(ImportSource.Chrome, ChromiumProfiles, ChromiumPasswordStores,
        (contents, importedAt) => ChromiumSession.Read(contents, importedAt), ChromeBookmarks.Read, chromium: true, extensions: true,
        sessionFiles: ChromiumSessionFiles, bookmarkFiles: ChromiumBookmarkFiles, history: ChromiumProfileHistory);
    public static readonly InstalledBrowser Safari = new(ImportSource.Safari, SafariProfiles, _ => [], SafariSession.Read,
        SafariBookmarks.Read, history: SafariHistory.Read);
    public static readonly InstalledBrowser Firefox = new(ImportSource.Firefox, FirefoxProfiles, _ => [], FirefoxSession.Read,
        bookmarks: null, bookmarkDatabase: MozillaPlaces.Bookmarks, history: MozillaPlaces.History);
    public static readonly InstalledBrowser ChromeBeta = ChromiumFamily(ImportSource.ChromeBeta);
    public static readonly InstalledBrowser ChromeDev = ChromiumFamily(ImportSource.ChromeDev);
    public static readonly InstalledBrowser ChromeCanary = ChromiumFamily(ImportSource.ChromeCanary);
    public static readonly InstalledBrowser Chromium = ChromiumFamily(ImportSource.Chromium);
    public static readonly InstalledBrowser Brave = ChromiumFamily(ImportSource.Brave);
    public static readonly InstalledBrowser Edge = ChromiumFamily(ImportSource.Edge);
    public static readonly InstalledBrowser Vivaldi = ChromiumFamily(ImportSource.Vivaldi, ChromiumSessionDialect.Vivaldi);
    public static readonly InstalledBrowser Opera = ChromiumFamily(ImportSource.Opera);
    public static readonly InstalledBrowser Dia = ChromiumFamily(ImportSource.Dia);
    public static readonly InstalledBrowser Comet = ChromiumFamily(ImportSource.Comet);
    public static readonly InstalledBrowser Aside = ChromiumFamily(ImportSource.Aside);
    public static readonly InstalledBrowser EgoLite = ChromiumFamily(ImportSource.EgoLite);
    /// A browser Ode does not list, whose passwords it cannot open.
    public static readonly InstalledBrowser OtherChromium = new(ImportSource.OtherChromium, ChromiumProfiles, _ => [],
        (contents, importedAt) => ChromiumSession.Read(contents, importedAt), ChromeBookmarks.Read, chromium: true, extensions: true,
        sessionFiles: ChromiumSessionFiles, bookmarkFiles: ChromiumBookmarkFiles, history: ChromiumProfileHistory);

    public static IReadOnlyList<InstalledBrowser> All { get; } = [Arc, Zen, Chrome, Safari, Firefox, ChromeBeta, ChromeDev, ChromeCanary,
        Chromium, Brave, Edge, Vivaldi, Opera, Dia, Comet, Aside, EgoLite, OtherChromium];

    /// The largest session file an import reads.
    public const long MaximumSessionBytes = 512L * 1024 * 1024;
    /// The largest bookmark file an import reads.
    public const long MaximumBookmarkBytes = 50L * 1024 * 1024;
    /// The largest list of profiles a Mozilla browser keeps that an import reads.
    private const long MaximumProfileListBytes = 1024 * 1024;

    private const string ChromiumDefaultProfile = "Default";
    private const string ChromiumProfilePrefix = "Profile ";
    /// Where Opera keeps the profiles beside the one at its data folder's root.
    private const string ChromiumSideProfiles = "_side_profiles";
    /// What every Chromium profile keeps, and only a profile keeps.
    private const string ChromiumPreferences = "Preferences";
    /// What Chrome's first profile is called when the person never named it.
    private const string ChromiumDefaultName = "Personal";
    /// Chrome's latest session and the earlier ones it keeps beside it. Its
    /// `Tabs_` files hold recently closed tabs, which no import brings.
    private const string ChromiumCurrentSession = "Current Session";
    private const string ChromiumSessionPrefix = "Session_";
    private const string ZenSessionName = "zen-sessions.jsonlz4";
    private const string MozillaProfileList = "profiles.ini";

    /// A Chromium profile's bookmarks, and those of the account a signed-in
    /// profile syncs, which it keeps apart; and its saved passwords, kept the
    /// same two ways.
    private static readonly string[] ChromiumBookmarkNames = ["Bookmarks", "AccountBookmarks"];
    private static readonly string[] ChromiumPasswordStoreNames = ["Login Data", "Login Data For Account"];
    private static readonly string[] FirefoxSessionNames = ["recovery.jsonlz4", "sessionstore.jsonlz4"];

    #endregion

    #region Types

    private delegate IReadOnlyList<SessionDraft> SessionReader(byte[] contents, DateTimeOffset importedAt);

    private delegate void BookmarkReader(byte[] contents, DateTimeOffset importedAt, BookmarkDraft draft);

    /// Reads bookmarks from a database the browser may hold open, by its path.
    private delegate void BookmarkDatabaseReader(string path, DateTimeOffset importedAt, BookmarkDraft draft);

    /// The Spaces read from the session at `path`, with what the browser keeps
    /// beside it on those an import makes with `room` for them.
    private delegate IReadOnlyList<SessionDraft> SessionCompleter(string path, IReadOnlyList<SessionDraft> drafts, int room,
        DateTimeOffset importedAt, ICollection<Rejection> problems);

    #endregion

    #region Variables

    public ImportSource Source { get; }

    private readonly Func<ImportFolder, IReadOnlyList<ImportProfile>> profiles;
    private readonly Func<ImportFolder, IReadOnlyList<ImportPasswordStore>> passwordStores;
    private readonly SessionReader sessions;
    private readonly BookmarkReader? bookmarks;
    private readonly BookmarkDatabaseReader? bookmarkDatabase;
    /// The addresses a profile visited, read from its folder, which come with
    /// the first Space the profile brings.
    private readonly Func<string, ICollection<Rejection>, IReadOnlyList<SessionHistoryEntry>>? history;
    /// The session files a read tries for a profile's session, that one first,
    /// and the bookmark files it reads together for a profile's bookmarks.
    private readonly Func<string, IReadOnlyList<string>> sessionFiles;
    private readonly Func<string, IReadOnlyList<string>> bookmarkFiles;
    /// Whether the browser is built on Chromium, so each profile folder an
    /// import reads is a Chromium profile, holding its sign-ins.
    private readonly bool keepsChromiumProfiles;
    private readonly bool offersExtensions;
    private readonly SessionCompleter? completes;

    #endregion

    #region Constructors

    private InstalledBrowser(ImportSource source, Func<ImportFolder, IReadOnlyList<ImportProfile>> profiles,
        Func<ImportFolder, IReadOnlyList<ImportPasswordStore>> passwordStores, SessionReader sessions, BookmarkReader? bookmarks,
        bool chromium = false, bool extensions = false, Func<string, IReadOnlyList<string>>? sessionFiles = null,
        Func<string, IReadOnlyList<string>>? bookmarkFiles = null, SessionCompleter? completes = null,
        BookmarkDatabaseReader? bookmarkDatabase = null, Func<string, ICollection<Rejection>, IReadOnlyList<SessionHistoryEntry>>? history = null) {
        Source = source;
        this.bookmarkDatabase = bookmarkDatabase;
        this.history = history;
        this.completes = completes;
        keepsChromiumProfiles = chromium;
        offersExtensions = extensions;
        this.profiles = profiles;
        this.passwordStores = passwordStores;
        this.sessions = sessions;
        this.bookmarks = bookmarks;
        this.sessionFiles = sessionFiles ?? (path => [path]);
        this.bookmarkFiles = bookmarkFiles ?? (path => [path]);
    }

    #endregion

    #region Actions - Lookup

    public static InstalledBrowser Of(ImportSource source) => All.First(browser => browser.Source == source);

    /// A browser built on Chromium that keeps Chrome's layout, read as Chrome
    /// is, its session numbered as `dialect` numbers it.
    private static InstalledBrowser ChromiumFamily(ImportSource source, ChromiumSessionDialect? dialect = null) =>
        new(source, ChromiumProfiles, ChromiumPasswordStores, (contents, importedAt) => ChromiumSession.Read(contents, importedAt, dialect),
            ChromeBookmarks.Read, chromium: true, extensions: true, sessionFiles: ChromiumSessionFiles, bookmarkFiles: ChromiumBookmarkFiles,
            history: ChromiumProfileHistory);

    /// The history a Chromium profile keeps in its folder.
    private static IReadOnlyList<SessionHistoryEntry> ChromiumProfileHistory(string profilePath, ICollection<Rejection> problems) =>
        ChromiumHistory.Read(Path.Combine(profilePath, ChromiumHistory.FileName), problems);

    #endregion

    #region Actions - Finding

    /// What the browser keeps in `folder`.
    public ImportData Find(string folder) {
        var data = new ImportFolder(folder);
        return new(profiles(data), passwordStores(data));
    }

    private static IReadOnlyList<ImportProfile> ArcProfiles(ImportFolder folder) =>
        folder.File("StorableSidebar.json") is { } sidebar
            ? [new ImportProfile("arc", ImportSource.Arc.Title, null, sidebar, folder.Child("User Data").Child(ChromiumDefaultProfile).Path)] : [];

    /// Zen's profiles that keep a session, each named as the person named it,
    /// the one used last first. A folder holding a session itself is the one
    /// profile.
    private static IReadOnlyList<ImportProfile> ZenProfiles(ImportFolder folder) {
        var names = MozillaProfileNames(folder);
        IReadOnlyList<ImportFolder> candidates = folder.File(ZenSessionName) is not null ? [folder] : folder.Folders();
        return [.. candidates.Select(profile => (Profile: profile, Session: profile.Newest([ZenSessionName])))
            .Where(found => found.Session is not null).OrderByDescending(found => ImportFolder.Changed(found.Session!))
            .Select(found => new ImportProfile(found.Profile.Name, MozillaProfileName(names, found.Profile), null, found.Session,
                found.Profile.Path))];
    }

    /// Safari's one profile: its bookmarks, its last session and, in the same
    /// folder, its history.
    private static IReadOnlyList<ImportProfile> SafariProfiles(ImportFolder folder) {
        string? bookmarks = folder.File("Bookmarks.plist"), session = folder.File("LastSession.plist");
        bool history = folder.File(SafariHistory.FileName) is not null;
        return bookmarks is null && session is null && !history ? []
            : [new ImportProfile("safari", ImportSource.Safari.Title, bookmarks, session, history ? folder.Path : null)];
    }

    /// Firefox's profiles that keep a session, each named as the person named
    /// it, in the order of their folders.
    private static IReadOnlyList<ImportProfile> FirefoxProfiles(ImportFolder folder) {
        var names = MozillaProfileNames(folder);
        return [.. folder.Folders().Select(profile => profile.Newest(FirefoxSessionNames) is { } session
            ? new ImportProfile(profile.Name, MozillaProfileName(names, profile), profile.File(MozillaPlaces.FileName), session,
                profile.Path)
            : null).OfType<ImportProfile>()];
    }

    /// Chrome's profiles: those its `Local State` names and the profile
    /// folders it keeps, the first profile first, each named as the person
    /// named it, with its bookmarks, or its account's where it keeps only
    /// those, and its latest session.
    private static IReadOnlyList<ImportProfile> ChromiumProfiles(ImportFolder folder) {
        var names = ChromiumProfileNames(folder);
        return [.. ChromiumProfileFolders(folder, names).Select(found => {
            string? bookmarks = ChromiumBookmarkNames.Select(found.Profile.File).FirstOrDefault(path => path is not null);
            string? session = found.Profile.Child("Sessions").Newest([ChromiumCurrentSession], [ChromiumSessionPrefix]);
            return bookmarks is null && session is null ? null
                : new ImportProfile(found.Id, found.Name, bookmarks, session, found.Profile.Path);
        }).OfType<ImportProfile>()];
    }

    /// The saved-password stores of the Chromium profiles below `root`: each
    /// profile's own, then its account's.
    private static IReadOnlyList<ImportPasswordStore> ChromiumPasswordStores(ImportFolder root) {
        var names = ChromiumProfileNames(root);
        return [.. ChromiumProfileFolders(root, names).SelectMany(found => ChromiumPasswordStoreNames.Select(found.Profile.File)
            .OfType<string>().Select(store => new ImportPasswordStore(found.Id, found.Name, store)))];
    }

    /// The profile folders of the Chromium data in `root`, each with the name
    /// the person gave it: the profile at the root itself, where Opera keeps
    /// its first, then those `Local State` names and the profile folders kept
    /// beside it, the first profile first, then Opera's others.
    private static IReadOnlyList<(string Id, string Name, ImportFolder Profile)> ChromiumProfileFolders(ImportFolder root,
        IReadOnlyDictionary<string, string> names) {
        List<(string Id, string Name, ImportFolder Profile)> found = [];
        if (root.File(ChromiumPreferences) is not null)
            found.Add((root.Name, names.GetValueOrDefault(root.Name) ?? ChromiumDefaultName, root));
        var directories = names.Keys.Where(key => !key.Contains('/', StringComparison.Ordinal) && key != root.Name)
            .Union(root.Folders().Select(profile => profile.Name).Where(IsChromiumProfile), StringComparer.Ordinal);
        found.AddRange(directories.Order(ChromiumProfileOrder.Instance)
            .Select(directory => (directory, ChromiumProfileName(names, directory), root.Child(directory))));
        found.AddRange(root.Child(ChromiumSideProfiles).Folders().Where(profile => profile.File(ChromiumPreferences) is not null)
            .Select(profile => {
                string id = $"{ChromiumSideProfiles}/{profile.Name}";
                return (id, names.GetValueOrDefault(id) ?? names.GetValueOrDefault(profile.Name) ?? profile.Name, profile);
            }));
        return found;
    }

    private static bool IsChromiumProfile(string name) =>
        name == ChromiumDefaultProfile || name.StartsWith(ChromiumProfilePrefix, StringComparison.Ordinal);

    private static string ChromiumProfileName(IReadOnlyDictionary<string, string> names, string directory) =>
        names.TryGetValue(directory, out var name) ? name : directory == ChromiumDefaultProfile ? ChromiumDefaultName : directory;

    /// The name the person gave each profile, from `Local State`.
    private static Dictionary<string, string> ChromiumProfileNames(ImportFolder root) {
        using var state = root.Json("Local State");
        Dictionary<string, string> names = new(StringComparer.Ordinal);
        if (state is null) return names;
        var cache = ImportJson.Member(ImportJson.Member(state.RootElement, "profile"), "info_cache");
        foreach (var entry in ImportJson.Members(cache))
            if (ImportJson.Text(ImportJson.Member(entry.Value, "name")) is { } name && name.Trim().Length > 0) names[entry.Name] = name;
        return names;
    }

    /// The Chromium session file at `path`, then the earlier sessions the
    /// browser keeps beside it, the newest first.
    private static IReadOnlyList<string> ChromiumSessionFiles(string path) {
        var folder = new ImportFolder(Path.GetDirectoryName(path) ?? path);
        return [path, .. folder.Recent(name => name == ChromiumCurrentSession || name.StartsWith(ChromiumSessionPrefix, StringComparison.Ordinal))
            .Where(file => !IsSameFile(file, path))];
    }

    /// The Chromium bookmark file at `path`, then the other a signed-in
    /// profile keeps beside it, where it keeps one.
    private static IReadOnlyList<string> ChromiumBookmarkFiles(string path) {
        var folder = new ImportFolder(Path.GetDirectoryName(path) ?? path);
        return [path, .. ChromiumBookmarkNames.Select(folder.File).OfType<string>().Where(file => !IsSameFile(file, path))];
    }

    private static bool IsSameFile(string first, string second) =>
        string.Equals(Path.GetFullPath(first), Path.GetFullPath(second), StringComparison.Ordinal);

    /// The name the person gave each profile of a Mozilla browser, by the full
    /// path of its folder, from the `profiles.ini` the browser keeps beside
    /// `folder`, its folder of profiles; none when that cannot be read.
    private static Dictionary<string, string> MozillaProfileNames(ImportFolder folder) {
        Dictionary<string, string> names = new(StringComparer.Ordinal);
        string? root = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder.Path)));
        if (root is null || new ImportFolder(root).File(MozillaProfileList) is not { } list) return names;
        string text;
        try {
            text = Encoding.UTF8.GetString(ImportFile.Read(list, MaximumProfileListBytes, new FileUnreadable(), new FileUnreadable()));
        } catch (Rejected) {
            return names;
        }
        string? name = null, location = null;
        bool isRelative = true;
        void Keep() {
            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(location)) return;
            if (FullPath(isRelative ? Path.Combine(root, location) : location) is { } path) names[path] = name.Trim();
        }
        foreach (string line in text.Split('\n').Select(line => line.Trim())) {
            if (line.StartsWith('[')) {
                Keep();
                (name, location, isRelative) = (null, null, true);
                continue;
            }
            int equals = line.IndexOf('=', StringComparison.Ordinal);
            if (equals <= 0) continue;
            string key = line[..equals].Trim(), value = line[(equals + 1)..].Trim();
            if (key == "Name") name = value;
            else if (key == "Path") location = value.Replace('/', Path.DirectorySeparatorChar);
            else if (key == "IsRelative") isRelative = value != "0";
        }
        Keep();
        return names;
    }

    private static string MozillaProfileName(IReadOnlyDictionary<string, string> names, ImportFolder profile) =>
        FullPath(profile.Path) is { } path && names.TryGetValue(path, out var name) ? name : profile.Name;

    private static string? FullPath(string path) {
        try {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        } catch (Exception error) when (error is ArgumentException or NotSupportedException or PathTooLongException) {
            return null;
        }
    }

    #endregion

    #region Actions - Reading

    /// The Spaces `profiles` bring, up to the most a workspace holds, and what
    /// they leave out. See `ReadImport`. `histories` takes the whole history
    /// each Space brings, with its visits, by the Space's identity: the Space
    /// itself holds only its newest addresses, as a Space's history does.
    public ImportedSpaces Read(IReadOnlyList<ImportProfile> profiles, ImportSpaceNames names, IIdSource ids,
        DateTimeOffset now, IDictionary<Guid, IReadOnlyList<SessionHistoryEntry>>? histories = null) {
        List<SpaceState> spaces = [];
        List<ImportSpaceExtensions> extensions = [];
        List<ImportSpaceProfile> folders = [];
        List<ImportLeftOut> leftOut = [];
        foreach (var profile in profiles) {
            int room = BrowserDataFile.MaximumSpaces - spaces.Count;
            if (Source.NamesItsSpaces) {
                if (profile.SessionPath is not { } path) continue;
                IReadOnlyList<SessionDraft> drafts;
                try {
                    drafts = Sessions(path, now);
                } catch (Rejected rejected) {
                    leftOut.Add(new(profile.Name, rejected.Rejection));
                    continue;
                }
                List<Rejection> historyProblems = [];
                drafts = completes is not null ? completes(path, drafts, room, now, historyProblems)
                    : WithHistory(drafts, ProfileHistory(profile, historyProblems));
                leftOut.AddRange(historyProblems.Distinct().Select(problem => new ImportLeftOut(profile.Name, problem)));
                var named = SessionDraft.Spaces(drafts, Source, names, ids, now, room, leftOut);
                spaces.AddRange(named.Select(made => made.Space));
                foreach (var (space, draft) in named)
                    if (draft.History is { Count: > 0 } history && histories is not null) histories[space.Id] = history;
                var read = named.Select(made => (made.Space, made.Draft.Profile)).ToArray();
                AddProfiles(folders, profile, read);
                AddExtensions(extensions, profile, read);
            } else if (room == 0) {
                leftOut.Add(new(profile.Name, new SessionOverLimits()));
            } else if (ProfileSpace(profile, names, ids, now, leftOut, out var history) is { } space) {
                spaces.Add(space);
                if (history.Count > 0 && histories is not null) histories[space.Id] = history;
                AddProfiles(folders, profile, [(space, null)]);
                AddExtensions(extensions, profile, [(space, null)]);
            }
        }
        if (spaces.Count == 0) throw new Rejected(leftOut.LastOrDefault()?.Reason ?? new SessionHasNoTabs());
        return new(spaces, extensions, leftOut, folders);
    }

    /// The Space `profile` brings, named after it: the tabs of its open
    /// windows, each window that fits beside the first, and ahead of them as
    /// many of its bookmarks as fit in the room they leave. What could not be
    /// read or did not fit is left out in `leftOut` under the profile's name;
    /// a profile that brings nothing keeps every distinct problem, or is
    /// reported as holding nothing when no actual problem was found.
    private SpaceState? ProfileSpace(ImportProfile profile, ImportSpaceNames names, IIdSource ids, DateTimeOffset now,
        List<ImportLeftOut> leftOut, out IReadOnlyList<SessionHistoryEntry> visited) {
        List<Rejection> bookmarkProblems = [], sessionProblems = [], historyProblems = [];
        SpaceState? windows = null;
        visited = ProfileHistory(profile, historyProblems);
        if (profile.SessionPath is { } sessionPath) {
            try {
                windows = SessionDraft.Merged(WithHistory(Sessions(sessionPath, now), visited), Source, names, ids, now,
                    out var problem);
                if (problem is not null) sessionProblems.Add(problem);
            } catch (Rejected rejected) {
                sessionProblems.Add(rejected.Rejection);
            }
        }
        SpaceState? marks = null;
        if (profile.BookmarksPath is { } bookmarkPath && (bookmarks is not null || bookmarkDatabase is not null)) {
            try {
                marks = Bookmarks(bookmarkPath, now, bookmarkProblems).Space(Source, ids, now,
                    SessionDraft.MaximumTabs - (windows?.Tabs.Count ?? 0), FolderTree.MaximumCount - (windows?.Folders.Count ?? 0), out bool cut);
                if (cut) bookmarkProblems.Add(new BookmarksOverLimits());
            } catch (Rejected rejected) {
                bookmarkProblems.Add(rejected.Rejection);
            }
        }
        var problems = bookmarkProblems.Concat(sessionProblems).Concat(historyProblems).Distinct().ToArray();
        leftOut.AddRange(problems.Select(problem => new ImportLeftOut(profile.Name, problem)));
        if ((Joined(marks, windows) ?? HistoryOnly(profile, visited, names, ids, now)) is not { } combined) {
            if (problems.Length == 0)
                leftOut.Add(new(profile.Name, profile.SessionPath is null ? new BookmarksHaveNoLinks() : new SessionHasNoTabs()));
            return null;
        }
        return combined with { Settings = combined.Settings with { Name = profile.Name, Symbol = Source.Symbol, Accent = Source.Accent } };
    }

    /// Names for each of `spaces` the folder of the Chromium profile it was
    /// read from, when the browser is built on Chromium and `profile` names
    /// its folder; see `ProfileFolder`.
    private void AddProfiles(List<ImportSpaceProfile> folders, ImportProfile profile,
        IEnumerable<(SpaceState Space, string? Profile)> spaces) {
        if (!keepsChromiumProfiles || profile.ProfilePath is not { } path) return;
        var first = new ImportFolder(path);
        folders.AddRange(spaces.Select(read => new ImportSpaceProfile(read.Space.Id, ProfileFolder(first, read.Profile).Path)));
    }

    /// Offers each of `spaces` the Web Store extensions its profile has
    /// installed, when the browser keeps them where Ode reads them and the
    /// profile has any. Each profile is read once; see `ProfileFolder`.
    private void AddExtensions(List<ImportSpaceExtensions> offers, ImportProfile profile,
        IEnumerable<(SpaceState Space, string? Profile)> spaces) {
        if (!offersExtensions || profile.ProfilePath is not { } path) return;
        var first = new ImportFolder(path);
        Dictionary<string, IReadOnlyList<ImportExtension>> read = new(StringComparer.Ordinal);
        foreach (var (space, own) in spaces) {
            var folder = ProfileFolder(first, own);
            if (!read.TryGetValue(folder.Path, out var installed)) read[folder.Path] = installed = ChromiumExtensions.Read(folder);
            if (installed.Count > 0) offers.Add(new ImportSpaceExtensions(space.Id, installed));
        }
    }

    /// The profile folder a Space was read from: `first`, the folder of the
    /// profile it came with, or, for a Space that names a profile of its own,
    /// the folder of that name beside it, the way Arc keeps them.
    private static ImportFolder ProfileFolder(ImportFolder first, string? own) =>
        own is null ? first : new ImportFolder(System.IO.Path.GetDirectoryName(first.Path) ?? first.Path).Child(own);

    /// The windows or Spaces the session at `path` holds, or, when that file
    /// cannot be read or holds no tab, those of the newest earlier session the
    /// browser keeps beside it that does. Throws `Rejected` with what was
    /// wrong with the newest file when none can be read.
    private IReadOnlyList<SessionDraft> Sessions(string path, DateTimeOffset now) {
        Rejection? failure = null;
        IReadOnlyList<SessionDraft>? empty = null;
        foreach (string file in sessionFiles(path)) {
            try {
                var drafts = Session(file, now);
                if (drafts.Any(draft => draft.Tabs.Count > 0)) return drafts;
                empty ??= drafts;
            } catch (Rejected rejected) {
                failure ??= rejected.Rejection;
            }
        }
        return empty ?? throw new Rejected(failure ?? new SessionUnrecognized());
    }

    private IReadOnlyList<SessionDraft> Session(string path, DateTimeOffset now) {
        var contents = ImportFile.Read(path, MaximumSessionBytes, new SessionTooLarge(), new SessionUnrecognized());
        try {
            return sessions(contents, now);
        } catch (Exception error) when (error is not Rejected) {
            throw new Rejected(new SessionUnrecognized());
        }
    }

    /// The bookmarks of the file at `path` and of each other file the browser
    /// keeps them in beside it, as one. A file that cannot be read is skipped,
    /// with what was wrong with it in `problems`.
    private BookmarkDraft Bookmarks(string path, DateTimeOffset now, ICollection<Rejection> problems) {
        var draft = new BookmarkDraft();
        if (bookmarkDatabase is not null) {
            try {
                draft.BeginFile();
                bookmarkDatabase(path, now, draft);
            } catch (Rejected rejected) {
                problems.Add(rejected.Rejection);
            }
            return draft;
        }
        foreach (string file in bookmarkFiles(path)) {
            try {
                var contents = ImportFile.Read(file, MaximumBookmarkBytes, new BookmarksTooLarge(), new FileUnreadable());
                draft.BeginFile();
                bookmarks!(contents, now, draft);
            } catch (Rejected rejected) {
                problems.Add(rejected.Rejection);
            } catch (Exception error) when (error is not Rejected) {
                problems.Add(new BookmarksUnrecognized());
            }
        }
        return draft;
    }

    /// The addresses the profile visited, read once from its folder; none
    /// where Ode reads no history for this browser or the profile names no
    /// folder.
    private IReadOnlyList<SessionHistoryEntry> ProfileHistory(ImportProfile profile, ICollection<Rejection> problems) =>
        history is not null && profile.ProfilePath is { } folder ? history(folder, problems) : [];

    /// A Space bringing only `visited`, the history of a profile with nothing
    /// open and nothing bookmarked, so what the person read still comes with
    /// them; null when the profile has none.
    private SpaceState? HistoryOnly(ImportProfile profile, IReadOnlyList<SessionHistoryEntry> visited, ImportSpaceNames names,
        IIdSource ids, DateTimeOffset now) {
        if (visited.Count == 0) return null;
        var made = SessionDraft.Spaces([new SessionDraft(1, profile.Name, [], [], History: visited)], Source, names, ids, now,
            room: 1, leftOut: []);
        return made.Count == 1 ? made[0].Space : null;
    }

    /// `drafts` with `visited`, the history the profile keeps, on the first
    /// that holds a tab, which brings it for the profile; unchanged when the
    /// profile has none.
    private static IReadOnlyList<SessionDraft> WithHistory(IReadOnlyList<SessionDraft> drafts, IReadOnlyList<SessionHistoryEntry> visited) {
        int first = drafts.ToList().FindIndex(draft => draft.Tabs.Count > 0);
        if (first < 0 || visited.Count == 0) return drafts;
        return [.. drafts.Select((draft, index) => index == first ? draft with { History = [.. draft.History ?? [], .. visited] } : draft)];
    }

    /// `first` with the folders, tabs and history of `second` after its own,
    /// or whichever of the two there is.
    private static SpaceState? Joined(SpaceState? first, SpaceState? second) => first is null ? second : second is null ? first
        : first with {
            Folders = [.. first.Folders, .. second.Folders],
            Tabs = [.. first.Tabs, .. second.Tabs],
            History = [.. first.History, .. second.History]
        };

    #endregion
}
