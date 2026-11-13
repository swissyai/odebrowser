using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

using OdeCore.Contracts;

namespace OdeCore.Application;

/// The dated exports Ode keeps in a folder the person chose. Each export is a
/// folder named for the local time it was written, `yyyy-MM-dd HH.mm.ss`,
/// holding one file for each `ExportFormat`: the browser-data JSON an import
/// reads back whole, the Netscape bookmark file every browser imports, and
/// the history in JSON Lines. Passwords, cookies and website data are never
/// part of any of them.
///
/// An export is written whole into a hidden folder beside the others and
/// renamed into place, so a dated folder always holds a whole export. The
/// newest `Kept` exports stay; an older one is removed only when it holds
/// nothing but an export's files, so a folder the person keeps there under
/// a dated name is never touched.
internal static partial class ExportFolder {
    #region Static Variables

    /// How many dated exports a folder keeps.
    public const int Kept = 7;

    private const string NameFormat = "yyyy-MM-dd HH.mm.ss";
    private const string PartialPrefix = ".ode-export-";

    #endregion

    #region Actions - Reading

    /// The dated exports in `folder`, newest first, by name.
    public static IReadOnlyList<string> List(string folder) {
        if (!Directory.Exists(folder)) return [];
        try {
            return [.. Directory.EnumerateDirectories(folder)
                .Where(path => DatedName().IsMatch(Path.GetFileName(path)) && HoldsOnlyAnExport(path))
                .OrderByDescending(path => Path.GetFileName(path), StringComparer.Ordinal)];
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            return [];
        }
    }

    /// What a person would miss from an export that predates a change: each
    /// Space's name and look, its pinned and saved tabs and folders, and how
    /// many tabs its archive holds. Open tabs and history change with every
    /// page, so they wait for the next daily export.
    public static string Fingerprint(IEnumerable<SpaceState> spaces) {
        ArgumentNullException.ThrowIfNull(spaces);
        var text = new StringBuilder();
        foreach (var space in spaces) {
            text.Append("space ").Append(space.Id).Append(' ').Append(space.Settings.Name).Append(' ')
                .Append(space.Settings.Symbol).Append(' ').Append(space.Settings.Accent.Name).Append(' ')
                .Append(space.ArchivedTabs.Count.ToString(CultureInfo.InvariantCulture)).Append('\n');
            foreach (var folder in space.Folders.Where(folder => folder.Location != TabPlacement.Current))
                text.Append("folder ").Append(folder.Id).Append(' ').Append(folder.Location.Name).Append(' ')
                    .Append(folder.ParentId).Append(' ').Append(folder.Title).Append('\n');
            foreach (var tab in space.Tabs.Where(tab => tab.Placement != TabPlacement.Current))
                text.Append("tab ").Append(tab.Id).Append(' ').Append(tab.Placement.Name).Append(' ')
                    .Append(tab.FolderId).Append(' ').Append(tab.SavedUrl ?? tab.Url).Append('\n');
        }
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text.ToString())));
    }

    #endregion

    #region Actions - Writing

    /// Writes `documents` into a new dated folder in `folder`, named for
    /// `now` in `zone`, removes the exports past the newest `Kept`, and
    /// answers the new folder's path. Throws `Rejected` with
    /// `ExportFolderUnwritable` when the folder cannot be written, leaving
    /// the exports already there as they were.
    public static string Write(string folder, IReadOnlyList<ExportedDocument> documents, DateTimeOffset now, TimeZoneInfo zone) {
        ArgumentNullException.ThrowIfNull(documents);
        if (string.IsNullOrWhiteSpace(folder) || !Path.IsPathFullyQualified(folder)) throw new Rejected(new ExportFolderUnwritable());
        string partial = Path.Combine(folder, PartialPrefix + Guid.NewGuid().ToString("N"));
        string written;
        try {
            Directory.CreateDirectory(folder);
            RemovePartials(folder);
            Directory.CreateDirectory(partial);
            foreach (var document in documents) {
                using var stream = new FileStream(Path.Combine(partial, document.Format.FileName), FileMode.CreateNew, FileAccess.Write);
                stream.Write(document.Contents);
                stream.Flush(flushToDisk: true);
            }
            var at = TimeZoneInfo.ConvertTime(now, zone);
            while (true) {
                written = Path.Combine(folder, at.ToString(NameFormat, CultureInfo.InvariantCulture));
                if (!Directory.Exists(written) && !File.Exists(written)) break;
                at = at.AddSeconds(1);
            }
            Directory.Move(partial, written);
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException) {
            Remove(partial);
            throw new Rejected(new ExportFolderUnwritable());
        }
        Prune(folder);
        return written;
    }

    /// Removes the exports in `folder` past the newest `kept`. An export that
    /// cannot be removed stays for the next one.
    public static void Prune(string folder, int kept = Kept) {
        foreach (var path in List(folder).Skip(kept)) Remove(path);
    }

    /// Removes what an export that stopped partway left in `folder`.
    private static void RemovePartials(string folder) {
        foreach (var path in Directory.EnumerateDirectories(folder, PartialPrefix + "*")) Remove(path);
    }

    private static void Remove(string path) {
        try {
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        } catch (IOException) {
        } catch (UnauthorizedAccessException) {
        }
    }

    /// The folder at `path` holds the browser-data file and nothing an export
    /// does not write.
    private static bool HoldsOnlyAnExport(string path) {
        if (Directory.EnumerateDirectories(path).Any()) return false;
        var names = Directory.EnumerateFiles(path).Select(Path.GetFileName).ToHashSet(StringComparer.Ordinal);
        return names.Contains(ExportFormat.BrowserData.FileName)
            && names.All(name => ExportFormat.All.Any(format => format.FileName == name));
    }

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2}$", RegexOptions.CultureInvariant)]
    private static partial Regex DatedName();

    #endregion
}
