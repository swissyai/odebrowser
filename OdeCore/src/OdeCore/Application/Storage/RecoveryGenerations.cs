using System.Globalization;
using System.Text.RegularExpressions;

using OdeCore.Contracts;

namespace OdeCore.Application;

/// The dated copies of the session file kept in `Checkpoints` beside it, one
/// per launch, each named for when it was taken and what it held. The last
/// five launches are kept, and the newest copy of each of the last seven
/// days, within a cap on count and size that never removes the newest copy
/// or one a launch held back. A copy is written whole under a temporary name
/// and renamed into place, so a name in the folder is always a whole file.
///
/// Beside the copies, the folder keeps how many Spaces and tabs the person
/// removed since the newest copy was taken, which explains a session that
/// shrank, and the name of a copy a launch held back.
///
/// A copy kept before an update installs is named for the version it was
/// about to install. Those copies rotate on their own: the newest
/// `UpdateCopiesKept` stay, one per version, and the launches' rotation
/// neither counts nor removes them. A copy kept before a restore rotates the
/// same way: the newest `RestoreCopiesKept` stay.
internal static partial class RecoveryGenerations {
    #region Types

    /// How many Spaces, not counting any going away, and tabs a session holds.
    internal readonly record struct Counts(int Spaces, int Tabs) {
        public static Counts Of(SessionState session) =>
            new(session.StayingSpaces.Count, session.Spaces.Sum(space => space.Tabs.Count));

        /// What `next` holds fewer of than `previous`, which a removal explains.
        public static Counts Removed(SessionState previous, SessionState next) {
            var before = Of(previous);
            var after = Of(next);
            return new(Math.Max(0, before.Spaces - after.Spaces), Math.Max(0, before.Tabs - after.Tabs));
        }

        public static Counts operator +(Counts left, Counts right) => new(left.Spaces + right.Spaces, left.Tabs + right.Tabs);
    }

    #endregion

    #region Variables

    public const string DirectoryName = "Checkpoints";
    public const int LaunchesKept = 5;
    public const int DaysKept = 7;
    public const int MostKept = 14;
    public const long MostBytes = 1L << 30;
    public const int UpdateCopiesKept = 3;
    public const int RestoreCopiesKept = 3;
    private const string HeldFileName = "held";
    private const string RemovedFileName = "removed-by-person";
    private const string TimestampFormat = "yyyyMMdd'T'HHmmssfff'Z'";

    #endregion

    #region Actions - Reading

    /// The copies in `storageDirectory`'s `Checkpoints` folder, newest first.
    public static IReadOnlyList<RecoveryCopy> List(string storageDirectory) {
        string folder = Folder(storageDirectory);
        if (!Directory.Exists(folder)) return [];
        string? held = Held(storageDirectory);
        var generations = new List<RecoveryCopy>();
        foreach (var path in Directory.EnumerateFiles(folder, "session-*.sqlite")) {
            if (Parse(Path.GetFileName(path)) is not { } parsed) continue;
            long bytes;
            try {
                bytes = new FileInfo(path).Length;
            } catch (IOException) {
                continue;
            }
            generations.Add(new(parsed.Name, parsed.TakenAt, parsed.Counts.Spaces, parsed.Counts.Tabs, bytes,
                Held: parsed.Name == held, UpdateTo: parsed.UpdateTo, BeforeRestore: parsed.BeforeRestore));
        }
        return [.. generations.OrderByDescending(generation => generation.TakenAt).ThenByDescending(generation => generation.Name, StringComparer.Ordinal)];
    }

    /// The path of the copy named `name`, when it is one of the copies.
    public static string? PathOf(string storageDirectory, string name) {
        if (Parse(name) is null) return null;
        string path = Path.Combine(Folder(storageDirectory), name);
        return File.Exists(path) ? path : null;
    }

    /// The copy a launch held back, while the person has not restored it or
    /// chosen to keep the session that replaced it.
    public static string? Held(string storageDirectory) {
        try {
            string name = File.ReadAllText(Path.Combine(Folder(storageDirectory), HeldFileName)).Trim();
            return Parse(name) is null ? null : name;
        } catch (IOException) {
            return null;
        } catch (UnauthorizedAccessException) {
            return null;
        }
    }

    /// How many Spaces and tabs the person removed since the copy named `since`
    /// was taken; none when the record is for another copy or unreadable.
    public static Counts Removed(string storageDirectory, string since) {
        try {
            var lines = File.ReadAllLines(Path.Combine(Folder(storageDirectory), RemovedFileName));
            if (lines.Length >= 3 && lines[0] == since
                && int.TryParse(lines[1], NumberStyles.None, CultureInfo.InvariantCulture, out int spaces)
                && int.TryParse(lines[2], NumberStyles.None, CultureInfo.InvariantCulture, out int tabs))
                return new(spaces, tabs);
        } catch (IOException) {
        } catch (UnauthorizedAccessException) {
        }
        return default;
    }

    /// Whether a session holding `loaded` lost more than half of the Spaces or
    /// of the tabs `newest` held, beyond what the person removed. A loss of
    /// fewer than two is never one.
    public static bool LostMoreThanHalf(Counts newest, Counts loaded, Counts removed) {
        var explained = loaded + removed;
        return Lost(newest.Spaces, explained.Spaces) || Lost(newest.Tabs, explained.Tabs);

        static bool Lost(int before, int after) => before - after >= 2 && after * 2 < before;
    }

    #endregion

    #region Actions - Writing

    /// Moves the whole file at `temporary` into the folder as the copy taken
    /// at `takenAt` holding `counts`, kept before updating to `updateTo` when
    /// it names a version or before a restore when `beforeRestore`, and
    /// answers its name.
    public static string Install(string storageDirectory, string temporary, DateTimeOffset takenAt, Counts counts,
        string? updateTo = null, bool beforeRestore = false) {
        string folder = Folder(storageDirectory);
        CreateFolder(folder);
        var at = takenAt.ToUniversalTime();
        while (true) {
            string name = NameFor(at, counts, updateTo, beforeRestore);
            string path = Path.Combine(folder, name);
            if (!File.Exists(path)) {
                File.Move(temporary, path, overwrite: false);
                return name;
            }
            at = at.AddMilliseconds(1);
        }
    }

    /// Holds back the copy named `name` from rotation until the person
    /// restores it or keeps the session that replaced it.
    public static void Hold(string storageDirectory, string name) =>
        WriteWhole(Path.Combine(Folder(storageDirectory), HeldFileName), name);

    /// Lets the copy a launch held back rotate out again.
    public static void Release(string storageDirectory) {
        try {
            File.Delete(Path.Combine(Folder(storageDirectory), HeldFileName));
        } catch (IOException) {
        } catch (UnauthorizedAccessException) {
        }
    }

    /// Records that the person removed `removed` since the copy named `since`.
    public static void RecordRemoved(string storageDirectory, string since, Counts removed) =>
        WriteWhole(Path.Combine(Folder(storageDirectory), RemovedFileName),
            string.Join('\n', since, removed.Spaces.ToString(CultureInfo.InvariantCulture), removed.Tabs.ToString(CultureInfo.InvariantCulture)));

    /// Removes the copies the rotation no longer keeps, as of `now`, and
    /// answers their names. A copy that cannot be removed stays for the next
    /// launch.
    public static IReadOnlyList<string> Prune(string storageDirectory, DateTimeOffset now, int mostKept = MostKept,
        long mostBytes = MostBytes) {
        var listed = List(storageDirectory);
        var kept = new HashSet<string>(StringComparer.Ordinal);
        // Copies kept before updates: the newest of each version, newest first.
        var versions = new HashSet<string>(StringComparer.Ordinal);
        foreach (var update in listed.Where(generation => generation.UpdateTo is not null)) {
            if (versions.Count < UpdateCopiesKept && versions.Add(update.UpdateTo!)) kept.Add(update.Name);
            if (update.Held) kept.Add(update.Name);
        }
        // Copies kept before restores: the newest few.
        foreach (var restore in listed.Where(generation => generation.BeforeRestore).Take(RestoreCopiesKept)) kept.Add(restore.Name);
        foreach (var restore in listed.Where(generation => generation.BeforeRestore && generation.Held)) kept.Add(restore.Name);
        var all = listed.Where(generation => generation.UpdateTo is null && !generation.BeforeRestore).ToList();
        if (all.Count == 0) return Remove(storageDirectory, listed, kept);
        foreach (var generation in all.Take(LaunchesKept)) kept.Add(generation.Name);
        var today = now.UtcDateTime.Date;
        foreach (var day in all.GroupBy(generation => generation.TakenAt.UtcDateTime.Date)) {
            if ((today - day.Key).TotalDays < DaysKept) kept.Add(day.First().Name);
        }
        var pinned = new HashSet<string>(StringComparer.Ordinal) { all[0].Name };
        foreach (var generation in all.Where(generation => generation.Held)) {
            kept.Add(generation.Name);
            pinned.Add(generation.Name);
        }
        // Within the caps, the oldest copies the rotation keeps go first.
        var keptInOrder = all.Where(generation => kept.Contains(generation.Name)).ToList();
        int count = keptInOrder.Count;
        long bytes = keptInOrder.Sum(generation => generation.Bytes);
        foreach (var generation in Enumerable.Reverse(keptInOrder)) {
            if (count <= mostKept && bytes <= mostBytes) break;
            if (pinned.Contains(generation.Name)) continue;
            kept.Remove(generation.Name);
            count--;
            bytes -= generation.Bytes;
        }
        return Remove(storageDirectory, listed, kept);
    }

    /// Removes every copy in `listed` that is not in `kept`, and answers the
    /// names it removed; one that cannot be removed stays for the next launch.
    private static List<string> Remove(string storageDirectory, IReadOnlyList<RecoveryCopy> listed, HashSet<string> kept) {
        var removed = new List<string>();
        foreach (var generation in listed.Where(generation => !kept.Contains(generation.Name))) {
            try {
                File.Delete(Path.Combine(Folder(storageDirectory), generation.Name));
                removed.Add(generation.Name);
            } catch (IOException) {
            } catch (UnauthorizedAccessException) {
            }
        }
        return removed;
    }

    #endregion

    #region Actions - Names

    private static string Folder(string storageDirectory) => Path.Combine(storageDirectory, DirectoryName);

    private static void CreateFolder(string folder) {
        if (OperatingSystem.IsWindows()) Directory.CreateDirectory(folder);
        else Directory.CreateDirectory(folder, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }

    internal static string NameFor(DateTimeOffset takenAt, Counts counts, string? updateTo = null, bool beforeRestore = false) =>
        string.Create(CultureInfo.InvariantCulture,
            $"session-{takenAt.UtcDateTime.ToString(TimestampFormat, CultureInfo.InvariantCulture)}-{counts.Spaces}s-{counts.Tabs}t{(updateTo is not null ? "-update-" + updateTo : beforeRestore ? "-restore" : "")}.sqlite");

    /// Whether `version` can name a copy: a version or build as a release
    /// names it, letters, digits, dots and hyphens.
    public static bool IsUpdateVersion(string version) => UpdateVersionPattern().IsMatch(version);

    private static (string Name, DateTimeOffset TakenAt, Counts Counts, string? UpdateTo, bool BeforeRestore)? Parse(string name) {
        var match = NamePattern().Match(name);
        if (!match.Success) return null;
        if (!DateTime.TryParseExact(match.Groups["at"].Value, TimestampFormat, CultureInfo.InvariantCulture,
                DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var at)) return null;
        var update = match.Groups["update"];
        return (name, new DateTimeOffset(at, TimeSpan.Zero),
            new(int.Parse(match.Groups["spaces"].Value, CultureInfo.InvariantCulture), int.Parse(match.Groups["tabs"].Value, CultureInfo.InvariantCulture)),
            update.Success ? update.Value : null, match.Groups["restore"].Success);
    }

    [GeneratedRegex(@"^session-(?<at>\d{8}T\d{9}Z)-(?<spaces>\d{1,6})s-(?<tabs>\d{1,9})t(?:-update-(?<update>[0-9A-Za-z][0-9A-Za-z.\-]{0,39})|-(?<restore>restore))?\.sqlite$", RegexOptions.CultureInvariant)]
    private static partial Regex NamePattern();

    [GeneratedRegex(@"^[0-9A-Za-z][0-9A-Za-z.\-]{0,39}$", RegexOptions.CultureInvariant)]
    private static partial Regex UpdateVersionPattern();

    /// Writes `text` under a temporary name and renames it over `path`, so a
    /// reader sees the old text or the new, never part of either.
    private static void WriteWhole(string path, string text) {
        CreateFolder(Path.GetDirectoryName(path)!);
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            File.WriteAllText(temporary, text);
            File.Move(temporary, path, overwrite: true);
        } finally {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    #endregion
}
