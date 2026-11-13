using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

using OdeCore.Contracts;

namespace OdeCore.Application;

/// The history file an export writes, in JSON Lines: one JSON object a line
/// for each address a Space's history keeps, Space by Space in the
/// workspace's order and newest first within each. Every line holds `space`,
/// the Space's name, and `url`, `title`, `firstVisitedAt`, `lastVisitedAt`
/// and `visitCount` as the browser-data file spells a history entry, and
/// `visits`, the time of each visit this device keeps, oldest first, with
/// times in milliseconds since 1970 and keys sorted. With the history kept
/// beside the session, every address it keeps is written; without it, the
/// addresses the session holds, each with its first and latest visit. The
/// browser-data file carries the session's newest addresses; this one is for
/// tools that read a line at a time.
internal static class HistoryLines {
    #region Static Variables

    /// The largest file an export writes.
    public const int MaximumBytes = 512 * 1024 * 1024;

    private static readonly JsonWriterOptions Writer = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    #endregion

    #region Actions - Writing

    /// The file of `spaces`' history, read from `history` where the workspace
    /// keeps one. Throws `Rejected` with `ArchiveTooLarge` when it would be
    /// larger than `MaximumBytes`.
    public static byte[] Write(IEnumerable<SpaceState> spaces, DateTimeOffset exportedAt, HistoryStore? history) {
        ArgumentNullException.ThrowIfNull(spaces);
        // An import or navigation may still be queued when Export Now is requested.
        history?.Flush();
        var buffer = new MemoryStream();
        void Line(SpaceState space, BrowserDataHistoryEntry entry, IEnumerable<DateTimeOffset> visits) {
            var line = entry.Write();
            line["space"] = space.Settings.Name;
            line["visits"] = new JsonArray([.. visits.Select(visit => JsonValue.Create(ImportDate.UnixMilliseconds(visit)))]);
            using (var writer = new Utf8JsonWriter(buffer, Writer)) BrowserDataFile.WriteSorted(writer, line);
            buffer.WriteByte((byte)'\n');
            if (buffer.Length > MaximumBytes) throw new Rejected(new ArchiveTooLarge());
        }
        foreach (var space in spaces) {
            if (history is null) {
                foreach (var entry in space.History)
                    Line(space, BrowserDataHistoryEntry.From(entry),
                        entry.FirstVisitedAt == entry.LastVisitedAt ? [entry.LastVisitedAt] : [entry.FirstVisitedAt, entry.LastVisitedAt]);
                continue;
            }
            history.EachWithVisits(space.Id, kept => Line(space, BrowserDataHistoryEntry.From(kept.Place), kept.Visits));
        }
        return buffer.ToArray();
    }

    #endregion
}
