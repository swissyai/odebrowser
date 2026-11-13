using OdeCore.Contracts;

namespace OdeCore.Application;

/// What a Mozilla profile, Firefox's or Zen's, keeps in `places.sqlite`: the
/// addresses the person visited, in `moz_places` with their visits and latest
/// visit in microseconds since 1970, the time of each visit in
/// `moz_historyvisits`, and the bookmarks in `moz_bookmarks`
/// under the roots the browser shows, the toolbar first. The browser holds
/// the database open, so it is read from a copy (see `ImportDatabase`).
internal static class MozillaPlaces {
    #region Static Variables

    /// The database each Mozilla profile keeps its places in.
    public const string FileName = "places.sqlite";

    /// The addresses a person saw, most recently visited first.
    private const string HistoryQuery =
        "SELECT id, url, title, visit_count, last_visit_date FROM moz_places WHERE hidden = 0 AND last_visit_date > 0 "
        + "ORDER BY last_visit_date DESC";
    /// Each visit's place and time, without the visits a page's frames and
    /// embedded parts made, which the browser's own history leaves out too.
    private const string VisitQuery = "SELECT place_id, visit_date FROM moz_historyvisits WHERE visit_type NOT IN (4, 8)";
    /// Every bookmark and folder, with its link where it has one, in the order
    /// the browser shows them in their folders.
    private const string BookmarkQuery =
        "SELECT b.id, b.type, b.parent, b.title, b.dateAdded, p.url, b.guid FROM moz_bookmarks b "
        + "LEFT JOIN moz_places p ON p.id = b.fk ORDER BY b.parent, b.position";

    private const long LinkType = 1, FolderType = 2;
    /// Folders nest no deeper than this, so a damaged database cannot loop.
    private const int MaximumDepth = 64;

    /// The roots the browser shows, in its order, with the names it shows
    /// them by; its tags and its own root are not bookmarks the person filed.
    private static readonly (string Guid, string Title)[] ShownRoots = [
        ("toolbar_____", "Bookmarks Toolbar"), ("menu________", "Bookmarks Menu"),
        ("unfiled_____", "Other Bookmarks"), ("mobile______", "Mobile Bookmarks")];

    #endregion

    #region Types

    private sealed record Place(long Id, long Type, long Parent, string Title, long Added, string? Url, string Guid);

    #endregion

    #region Actions - Reading

    /// The web addresses the profile in `profilePath` visited, each once, the
    /// most recently visited first, with their visits; none when its database
    /// is missing or cannot be read. See `ImportedHistory` for how much one
    /// brings.
    public static IReadOnlyList<SessionHistoryEntry> History(string profilePath, ICollection<Rejection>? problems = null) =>
        ImportedHistory.Read(Path.Combine(profilePath, FileName), Visited, problems);

    /// Adds the bookmarks of the database at `path` to `draft`. A link without
    /// a usable time is dated `importedAt`. Throws `Rejected` with
    /// `BookmarksUnrecognized` for a database that is not Mozilla's places.
    public static void Bookmarks(string path, DateTimeOffset importedAt, BookmarkDraft draft) {
        ArgumentNullException.ThrowIfNull(draft);
        var places = ImportDatabase.Read<IReadOnlyList<Place>?>(path, Filed, null)
            ?? throw new Rejected(new BookmarksUnrecognized());
        var children = places.ToLookup(place => place.Parent);
        foreach (var (guid, title) in ShownRoots)
            if (places.FirstOrDefault(place => place.Guid == guid) is { } root && HoldsLinks(root, children, depth: 0))
                Append(root with { Title = title }, parent: null, depth: 0, children, draft, importedAt);
    }

    private static ImportedHistory Visited(nint connection) {
        var history = new ImportedHistory();
        if (Sqlite.sqlite3_prepare_v2(connection, HistoryQuery, -1, out var statement, 0) != Sqlite.Ok) {
            history.Failed();
            return history;
        }
        try {
            int status = Sqlite.Done;
            while (!history.AddressesOmitted && (status = Sqlite.sqlite3_step(statement)) == Sqlite.Row)
                history.Add(Sqlite.sqlite3_column_int64(statement, 0), Sqlite.ColumnText(statement, 1), Sqlite.ColumnText(statement, 2),
                    Date(Sqlite.sqlite3_column_int64(statement, 4)), Sqlite.sqlite3_column_int64(statement, 3));
            if (!history.AddressesOmitted) history.Finished(status);
        } finally {
            Sqlite.sqlite3_finalize(statement);
        }
        if (Sqlite.sqlite3_prepare_v2(connection, VisitQuery, -1, out var visits, 0) == Sqlite.Ok) {
            try {
                int status = Sqlite.Done;
                while (!history.VisitsOmitted && (status = Sqlite.sqlite3_step(visits)) == Sqlite.Row)
                    history.Visit(Sqlite.sqlite3_column_int64(visits, 0), Date(Sqlite.sqlite3_column_int64(visits, 1)));
                if (!history.VisitsOmitted) history.Finished(status);
            } finally {
                Sqlite.sqlite3_finalize(visits);
            }
        } else {
            history.Failed();
        }
        return history;
    }

    /// Every bookmark and folder the open database holds, or null when it has
    /// no bookmarks table.
    private static IReadOnlyList<Place>? Filed(nint connection) {
        if (Sqlite.sqlite3_prepare_v2(connection, BookmarkQuery, -1, out var statement, 0) != Sqlite.Ok) return null;
        List<Place> places = [];
        try {
            while (places.Count <= BookmarkDraft.MaximumBookmarks * 2 && Sqlite.sqlite3_step(statement) == Sqlite.Row)
                places.Add(new Place(
                    Sqlite.sqlite3_column_int64(statement, 0), Sqlite.sqlite3_column_int64(statement, 1),
                    Sqlite.sqlite3_column_int64(statement, 2), Sqlite.ColumnText(statement, 3),
                    Sqlite.sqlite3_column_int64(statement, 4), Sqlite.ColumnIsNull(statement, 5) ? null : Sqlite.ColumnText(statement, 5),
                    Sqlite.ColumnText(statement, 6)));
        } finally {
            Sqlite.sqlite3_finalize(statement);
        }
        return places;
    }

    /// Whether `place` is a link or holds one at any depth, so a root the
    /// person never filled makes no folder.
    private static bool HoldsLinks(Place place, ILookup<long, Place> children, int depth) =>
        IsLink(place) || (place.Type == FolderType && depth < MaximumDepth
            && children[place.Id].Any(child => child.Id != place.Id && HoldsLinks(child, children, depth + 1)));

    private static void Append(Place place, Guid? parent, int depth, ILookup<long, Place> children, BookmarkDraft draft,
        DateTimeOffset importedAt) {
        if (IsLink(place)) {
            draft.AppendBookmark(place.Title, place.Url!, parent, Date(place.Added) ?? importedAt);
            return;
        }
        if (place.Type != FolderType || depth >= MaximumDepth || draft.AppendFolder(place.Title, parent, depth) is not { } folder)
            return;
        foreach (var child in children[place.Id].Where(child => child.Id != place.Id))
            Append(child, folder, depth + 1, children, draft, importedAt);
    }

    /// A link the person can open; the browser's saved searches (`place:`
    /// addresses) are not.
    private static bool IsLink(Place place) =>
        place.Type == LinkType && place.Url is { } url && !url.StartsWith("place:", StringComparison.Ordinal);

    /// A time Mozilla keeps in microseconds since 1970, when it is positive.
    private static DateTimeOffset? Date(long microseconds) =>
        microseconds > 0 ? ImportDate.FromUnixMicroseconds(microseconds) : null;

    #endregion
}
