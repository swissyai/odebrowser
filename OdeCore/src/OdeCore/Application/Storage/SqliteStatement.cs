namespace OdeCore.Application;

/// One prepared statement of a `SqliteConnection`, run again with new values
/// as often as its owner likes. Each run binds its values, steps through the
/// rows it answers and resets, so the next run starts clean. Not thread-safe:
/// its connection's owner serializes every call.
internal sealed class SqliteStatement : IDisposable {
    #region Variables

    private readonly SqliteConnection connection;
    private nint handle;

    #endregion

    #region Constructors

    internal SqliteStatement(SqliteConnection connection, nint handle) {
        this.connection = connection;
        this.handle = handle;
    }

    #endregion

    #region Actions - Binding

    /// Binds `value` to the parameter at `index`, counted from one; null binds SQL NULL.
    public SqliteStatement Bind(int index, string? value) => Checked(Sqlite.BindText(handle, index, value));

    public SqliteStatement Bind(int index, long value) => Checked(Sqlite.sqlite3_bind_int64(handle, index, value));

    public SqliteStatement Bind(int index, double value) => Checked(Sqlite.sqlite3_bind_double(handle, index, value));

    public SqliteStatement Bind(int index, ReadOnlySpan<byte> value) => Checked(Sqlite.BindBlob(handle, index, value));

    public SqliteStatement BindNull(int index) => Checked(Sqlite.BindNull(handle, index));

    #endregion

    #region Actions - Running

    /// Runs the statement once with the values bound, ignoring any rows, and
    /// answers how many rows it changed.
    public int Run() {
        try {
            while (Step()) { }
            return connection.Changes;
        } finally {
            Reset();
        }
    }

    /// Runs the statement once with the values bound and hands `row` each row
    /// it answers, in order.
    public void Rows(Action<SqliteStatement> row) {
        try {
            while (Step()) row(this);
        } finally {
            Reset();
        }
    }

    /// The first row's value of `read`, or `fallback` when the statement
    /// answers no row.
    public T First<T>(Func<SqliteStatement, T> read, T fallback) {
        try {
            return Step() ? read(this) : fallback;
        } finally {
            Reset();
        }
    }

    /// Moves to the next row: true at a row, false once the statement is done.
    private bool Step() {
        int result = Sqlite.sqlite3_step(handle);
        if (result == Sqlite.Row) return true;
        if (result == Sqlite.Done) return false;
        throw connection.Failure(result);
    }

    private void Reset() {
        Sqlite.sqlite3_reset(handle);
        Sqlite.sqlite3_clear_bindings(handle);
    }

    #endregion

    #region Actions - Columns

    public int Int(int column) => Sqlite.sqlite3_column_int(handle, column);

    public long Long(int column) => Sqlite.sqlite3_column_int64(handle, column);

    public double Double(int column) => Sqlite.sqlite3_column_double(handle, column);

    public string Text(int column) => Sqlite.ColumnText(handle, column);

    public byte[] Blob(int column) => Sqlite.ColumnBlob(handle, column);

    public bool IsNull(int column) => Sqlite.ColumnIsNull(handle, column);

    #endregion

    #region Actions - Lifetime

    public void Dispose() {
        if (handle == 0) return;
        Sqlite.sqlite3_finalize(handle);
        handle = 0;
    }

    private SqliteStatement Checked(int result) => result == Sqlite.Ok ? this : throw connection.Failure(result);

    #endregion
}
