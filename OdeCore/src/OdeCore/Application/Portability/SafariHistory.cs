using OdeCore.Contracts;

namespace OdeCore.Application;

/// Safari's history, its `History.db`: `history_items`, each address with
/// the visits Safari counted, and `history_visits`, each visit's time in
/// seconds since 2001 and the title the page had then. Safari holds the
/// database open and locked while it runs, so it is read from a copy (see
/// `ImportDatabase`).
internal static class SafariHistory {
    #region Static Variables

    /// The database Safari keeps its history in, beside its bookmarks.
    public const string FileName = "History.db";

    private const string ItemQuery = "SELECT id, url, visit_count FROM history_items";

    /// Each visit that loaded, oldest first, so the latest title wins.
    private const string VisitQuery =
        "SELECT history_item, visit_time, title FROM history_visits WHERE load_successful IS NOT 0 ORDER BY visit_time";

    #endregion

    #region Actions - Reading

    /// The web addresses Safari's folder at `folder` keeps in its history,
    /// each once, the most recently visited first, with their visits; none
    /// when the database is missing or cannot be read. An address with no
    /// visit that loaded is left out. See `ImportedHistory` for how much one
    /// brings.
    public static IReadOnlyList<SessionHistoryEntry> Read(string folder, ICollection<Rejection>? problems = null) =>
        ImportedHistory.Read(Path.Combine(folder, FileName), Entries, problems);

    private static ImportedHistory Entries(nint connection) {
        var history = new ImportedHistory();
        if (Sqlite.sqlite3_prepare_v2(connection, ItemQuery, -1, out var items, 0) != Sqlite.Ok) {
            history.Failed();
            return history;
        }
        try {
            int status = Sqlite.Done;
            while (!history.AddressesOmitted && (status = Sqlite.sqlite3_step(items)) == Sqlite.Row)
                history.Add(Sqlite.sqlite3_column_int64(items, 0), Sqlite.ColumnText(items, 1), "", lastVisitedAt: null,
                    Sqlite.sqlite3_column_int64(items, 2));
            if (!history.AddressesOmitted) history.Finished(status);
        } finally {
            Sqlite.sqlite3_finalize(items);
        }
        if (Sqlite.sqlite3_prepare_v2(connection, VisitQuery, -1, out var visits, 0) != Sqlite.Ok) {
            history.Failed();
            return history;
        }
        try {
            int status = Sqlite.Done;
            while (!history.VisitsOmitted && (status = Sqlite.sqlite3_step(visits)) == Sqlite.Row)
                history.Visit(Sqlite.sqlite3_column_int64(visits, 0), ImportDate.FromReferenceSeconds(Sqlite.sqlite3_column_double(visits, 1)),
                    Sqlite.ColumnIsNull(visits, 2) ? null : Sqlite.ColumnText(visits, 2));
            if (!history.VisitsOmitted) history.Finished(status);
        } finally {
            Sqlite.sqlite3_finalize(visits);
        }
        return history;
    }

    #endregion
}
