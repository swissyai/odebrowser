using OdeCore.Contracts;

namespace OdeCore.Application;

/// One connection to a session file and its `checkpoint(part, data)` table.
/// Not thread-safe: its owner serializes every call.
internal sealed partial class SqliteConnection : IDisposable {
    #region Variables

    /// A part is never empty and never larger than a session input may be.
    public const int MaximumPartBytes = NativeSessionAuthority.MaximumBytes;

    private const int BusyTimeoutMilliseconds = 2000;

    private nint handle;

    /// How many rows the latest statement that changed rows changed.
    public int Changes => Sqlite.sqlite3_changes(handle);

    /// How many rows every statement on this connection changed since it opened.
    public long TotalChanges => Sqlite.sqlite3_total_changes64(handle);

    #endregion

    #region Constructors

    private SqliteConnection(nint handle) => this.handle = handle;

    /// Opens `source` with SQLite's `flags`; a URI source needs `Sqlite.OpenUri`.
    /// A connection that can write orders its WAL checkpoints with
    /// `F_FULLFSYNC`: on Apple storage a plain `fsync` neither flushes the
    /// drive's cache nor orders writes, so a checkpoint the power cut short
    /// could leave the file half old and half new.
    public static SqliteConnection Open(string source, int flags) {
        int result = Sqlite.sqlite3_open_v2(source, out var handle, flags | Sqlite.OpenFullMutex, null);
        if (result != Sqlite.Ok) {
            string message = handle != 0 ? Sqlite.Message(handle) : "";
            if (handle != 0) Sqlite.sqlite3_close_v2(handle);
            throw new StorageException(SqliteFailure.ReasonFor(result), $"Cannot open {source}: {message} ({result})");
        }
        var connection = new SqliteConnection(handle);
        Sqlite.sqlite3_busy_timeout(handle, BusyTimeoutMilliseconds);
        if ((flags & Sqlite.OpenReadWrite) != 0) {
            try {
                connection.Execute("PRAGMA checkpoint_fullfsync=ON");
            } catch {
                connection.Dispose();
                throw;
            }
        }
        return connection;
    }

    #endregion

    #region Actions - Statements

    public void Execute(string sql) {
        int result = Sqlite.sqlite3_exec(handle, sql, 0, 0, 0);
        if (result != Sqlite.Ok) throw Failure(result);
    }

    /// Runs `body` inside `BEGIN IMMEDIATE … COMMIT`; any failure rolls back.
    public void InTransaction(Action body) {
        Execute("BEGIN IMMEDIATE");
        try {
            body();
            Execute("COMMIT");
        } catch {
            try { Execute("ROLLBACK"); } catch (StorageException) { }
            throw;
        }
    }

    /// Makes every commit of a file kept with a rollback journal, rather than
    /// a WAL, sync with `F_FULLFSYNC`, as a copy that must be whole on disk
    /// before it is renamed into place needs.
    public void RequireFullSync() => Execute("PRAGMA fullfsync=ON");

    /// What `PRAGMA name` answers on this connection, as text.
    public string Pragma(string name) => Query($"PRAGMA {name}", statement => {
        if (Sqlite.sqlite3_step(statement) != Sqlite.Row) throw Failure(Sqlite.sqlite3_extended_errcode(handle));
        return Sqlite.ColumnText(statement, 0);
    });

    /// The storage version the file records in `PRAGMA user_version`.
    public int ReadUserVersion() => Query("PRAGMA user_version", statement => {
        if (Sqlite.sqlite3_step(statement) != Sqlite.Row) throw Failure(Sqlite.sqlite3_extended_errcode(handle));
        return Sqlite.sqlite3_column_int(statement, 0);
    });

    private T Query<T>(string sql, Func<nint, T> body) {
        int prepared = Sqlite.sqlite3_prepare_v2(handle, sql, -1, out var statement, 0);
        if (prepared != Sqlite.Ok) throw Failure(prepared);
        try { return body(statement); } finally { Sqlite.sqlite3_finalize(statement); }
    }

    internal StorageException Failure(int result) =>
        new(SqliteFailure.ReasonFor(result), $"{Sqlite.Message(handle)} ({result})");

    /// `sql` prepared once, to run as often as the caller likes; the caller
    /// disposes it before the connection.
    public SqliteStatement Prepare(string sql) {
        int prepared = Sqlite.sqlite3_prepare_v2(handle, sql, -1, out var statement, 0);
        if (prepared != Sqlite.Ok) throw Failure(prepared);
        return new SqliteStatement(this, statement);
    }

    #endregion

    #region Actions - Parts

    /// A part's bytes, or null when the table does not hold it.
    public byte[]? Read(string part) {
        using var statement = Prepare("SELECT data FROM checkpoint WHERE part=?");
        var data = statement.Bind(1, part).First<byte[]?>(row => row.Blob(0), null);
        return data is null or { Length: > 0 and <= MaximumPartBytes }
            ? data : throw new StorageException(StorageFailure.Damaged, $"The stored part {part} is empty or too large.");
    }

    /// Every part the table holds.
    public IReadOnlyList<string> Parts() {
        var parts = new List<string>();
        using var statement = Prepare("SELECT part FROM checkpoint");
        statement.Rows(row => parts.Add(row.Text(0)));
        return parts;
    }

    public void Write(string part, byte[] data) {
        if (data.Length is 0 or > MaximumPartBytes)
            throw new StorageException(StorageFailure.Unavailable, $"The part {part} is empty or too large to store.");
        using var statement = Prepare("INSERT INTO checkpoint(part,data) VALUES(?,?) ON CONFLICT(part) DO UPDATE SET data=excluded.data");
        statement.Bind(1, part).Bind(2, data).Run();
    }

    public void Remove(string part) {
        using var statement = Prepare("DELETE FROM checkpoint WHERE part=?");
        statement.Bind(1, part).Run();
    }

    #endregion

    #region Actions - Backup

    /// Copies every committed page, WAL included, into a new standalone file
    /// at `destination` that has no sidecars.
    public void Backup(string destination) {
        var target = Open(destination, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        try {
            target.RequireFullSync();
            nint backup = Sqlite.sqlite3_backup_init(target.handle, "main", handle, "main");
            if (backup == 0) throw target.Failure(Sqlite.sqlite3_extended_errcode(target.handle));
            int step = Sqlite.sqlite3_backup_step(backup, -1);
            int finished = Sqlite.sqlite3_backup_finish(backup);
            if (step != Sqlite.Done) throw target.Failure(step);
            if (finished != Sqlite.Ok) throw target.Failure(finished);
            target.Execute("PRAGMA journal_mode=DELETE");
        } finally {
            target.Dispose();
        }
    }

    #endregion

    #region Actions - Lifetime

    public void Dispose() {
        if (handle == 0) return;
        Sqlite.sqlite3_close_v2(handle);
        handle = 0;
    }

    #endregion
}
