using OdeCore.Contracts;

namespace OdeCore.Application;

/// The history of a Chromium profile, its `History` database: the `urls`
/// table, with each address's title, visits and latest visit, and the
/// `visits` table, with the time of each visit the browser still keeps, in
/// microseconds since 1601. The browser may hold the database open, so it is
/// read from a copy (see `ImportDatabase`).
internal static class ChromiumHistory {
    #region Static Variables

    /// The database each Chromium profile keeps its history in.
    public const string FileName = "History";

    /// The addresses a person saw, most recently visited first.
    private const string Query =
        "SELECT id, url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC";

    /// Each visit's address and time, without the visits a page's frames
    /// made, which the browser's own history leaves out too.
    private const string VisitQuery = "SELECT url, visit_time FROM visits WHERE (transition & 255) NOT IN (3, 4)";

    #endregion

    #region Actions - Reading

    /// The web addresses of the database at `path`, each once, the most
    /// recently visited first, with their visits; none when it is missing or
    /// cannot be read. See `ImportedHistory` for how much one brings.
    public static IReadOnlyList<SessionHistoryEntry> Read(string path, ICollection<Rejection>? problems = null) =>
        ImportedHistory.Read(path, Entries, problems);

    /// The addresses and visits the open database holds.
    private static ImportedHistory Entries(nint connection) {
        var history = new ImportedHistory();
        if (Sqlite.sqlite3_prepare_v2(connection, Query, -1, out var statement, 0) != Sqlite.Ok) {
            history.Failed();
            return history;
        }
        try {
            int status = Sqlite.Done;
            while (!history.AddressesOmitted && (status = Sqlite.sqlite3_step(statement)) == Sqlite.Row) {
                long microseconds = Sqlite.sqlite3_column_int64(statement, 4);
                if (microseconds <= 0) continue;
                history.Add(Sqlite.sqlite3_column_int64(statement, 0), Sqlite.ColumnText(statement, 1), Sqlite.ColumnText(statement, 2),
                    ImportDate.FromWindowsMicroseconds(microseconds), Sqlite.sqlite3_column_int64(statement, 3));
            }
            if (!history.AddressesOmitted) history.Finished(status);
        } finally {
            Sqlite.sqlite3_finalize(statement);
        }
        if (Sqlite.sqlite3_prepare_v2(connection, VisitQuery, -1, out var visits, 0) == Sqlite.Ok) {
            try {
                int status = Sqlite.Done;
                while (!history.VisitsOmitted && (status = Sqlite.sqlite3_step(visits)) == Sqlite.Row) {
                    long microseconds = Sqlite.sqlite3_column_int64(visits, 1);
                    if (microseconds > 0)
                        history.Visit(Sqlite.sqlite3_column_int64(visits, 0), ImportDate.FromWindowsMicroseconds(microseconds));
                }
                if (!history.VisitsOmitted) history.Finished(status);
            } finally {
                Sqlite.sqlite3_finalize(visits);
            }
        } else {
            history.Failed();
        }
        return history;
    }

    #endregion
}
