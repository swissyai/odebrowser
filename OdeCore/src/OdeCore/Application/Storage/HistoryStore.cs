using OdeCore.Contracts;

namespace OdeCore.Application;

/// Every page the persistent workspace's Spaces visited, with each visit's
/// time, kept on this device in `history.sqlite` beside the session file.
/// The session keeps each Space's newest addresses as the list the Command
/// Bar ranks and sync carries; this store keeps everything the Space's
/// retention allows, however much that is, and never leaves the Mac.
///
/// A place is one address of one Space, with its title, first and latest
/// visit and how many visits it counts; every place holds at least one visit.
/// Private windows, Blank Windows and seeded sessions keep no store, so they
/// write nothing here, and the core reads a Space's rows only for a process
/// that may show the Space.
///
/// Writes run in order on one worker thread, many to a transaction, so a page
/// report never waits for the disk; each batch that commits announces
/// `StoredHistoryChanged`. Reads take a connection of their own, which sees
/// every committed batch and never waits for the writer. A store that cannot
/// be opened or written leaves the session as it is and reports the history
/// operation and reason separately. Failed writes remain in memory for retry;
/// a failed close explicitly refuses rather than claiming those writes saved.
internal sealed partial class HistoryStore : IDisposable {
    #region Static Variables

    public const string FileName = "history.sqlite";

    /// The version `PRAGMA user_version` records. A file from a newer release
    /// is set aside, never written over.
    private const int StorageVersion = 1;

    /// The most queued writes one transaction commits.
    private const int MaximumBatch = 64;

    private const string DamagedSuffix = ".damaged";
    private static readonly string[] SidecarSuffixes = ["-wal", "-shm"];
    private const UnixFileMode OwnerOnly = UnixFileMode.UserRead | UnixFileMode.UserWrite;

    #endregion

    #region Variables

    /// The connection the worker writes with, and its prepared statements.
    private readonly SqliteConnection writer;
    private readonly Dictionary<string, SqliteStatement> writing = new(StringComparer.Ordinal);
    /// The connection every read takes, one at a time, and its statements.
    private readonly SqliteConnection reader;
    private readonly Dictionary<string, SqliteStatement> reading = new(StringComparer.Ordinal);
    private readonly Lock readGate = new();

    private readonly Thread worker;
    private readonly Action<Change> announce;
    /// Guards the queue, the counts and the worker's wake-up; the worker and
    /// `Flush` wait on it.
    private readonly object queue = new();
    /// The queued writes, each with whether a change it makes is announced.
    private readonly Queue<(Action Write, bool Announces)> pending = new();
    /// How many writes were queued, and how many ran.
    private long queued, done;
    /// The newest revision a committed batch announced.
    private long revision;
    /// A failed batch stays queued until a new write or explicit flush retries it.
    private StorageException? failedWrite;
    private bool stopping, disposed;
    private volatile bool closed;

    /// Where the store keeps its file.
    public string Path { get; }

    internal long UnsavedWrites {
        get { lock (queue) return queued - done; }
    }

    /// The failed close's exact outcome, still readable after its connections
    /// are gone. Queued operations can contain several visits or imported pages.
    internal HistoryStorageFailed? CloseFailure {
        get {
            lock (queue) return disposed && done < queued
                ? new(HistoryStorageOperation.Close, failedWrite?.Reason ?? StorageFailure.Unavailable, queued - done) : null;
        }
    }

    #endregion

    #region Constructors

    private HistoryStore(string path, SqliteConnection writer, SqliteConnection reader, Action<Change> announce) {
        Path = path;
        this.writer = writer;
        this.reader = reader;
        this.announce = announce;
        worker = new Thread(Run) { IsBackground = true, Name = "Ode history store" };
        worker.Start();
    }

    /// Opens the store in `directory`, creating it when absent, or null when
    /// it cannot be used. A damaged file, or one a newer release wrote, is set
    /// aside beside it and a new one takes its place.
    public static HistoryStore? Open(string directory, Action<Change> announce) {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        ArgumentNullException.ThrowIfNull(announce);
        string path = System.IO.Path.Combine(directory, FileName);
        try {
            return Opened(path, announce);
        } catch (StorageException error) when (error.Reason == StorageFailure.Damaged) {
            announce(new HistoryStorageFailed(HistoryStorageOperation.Open, error.Reason, 0));
            try {
                SetAside(path);
            } catch (Exception move) when (move is IOException or UnauthorizedAccessException) {
                announce(new HistoryStorageFailed(HistoryStorageOperation.Recovery, Failure(move), 0));
                return null;
            }
        } catch (Exception error) when (error is StorageException or IOException or UnauthorizedAccessException) {
            announce(new HistoryStorageFailed(HistoryStorageOperation.Open, Failure(error), 0));
            return null;
        }
        try {
            return Opened(path, announce);
        } catch (Exception error) when (error is StorageException or IOException or UnauthorizedAccessException) {
            announce(new HistoryStorageFailed(HistoryStorageOperation.Open, Failure(error), 0));
            return null;
        }
    }

    private static HistoryStore Opened(string path, Action<Change> announce) {
        // Set the main file's mode before SQLite can create a WAL or write
        // history. Sidecars inherit it; also restrict sidecars from older opens.
        var options = new FileStreamOptions { Mode = FileMode.OpenOrCreate, Access = FileAccess.ReadWrite, Share = FileShare.ReadWrite };
        if (!OperatingSystem.IsWindows()) options.UnixCreateMode = OwnerOnly;
        using (new FileStream(path, options)) { }
        Restrict(path);
        foreach (string suffix in SidecarSuffixes) Restrict(path + suffix);
        var writer = SqliteConnection.Open(path, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        SqliteConnection? reader = null;
        try {
            int version = writer.ReadUserVersion();
            if (version > StorageVersion) throw new StorageException(StorageFailure.Damaged, "The history store is from a newer release.");
            writer.Execute("PRAGMA journal_mode=WAL");
            // Losing the last visits to a power cut costs less than a sync on every page.
            writer.Execute("PRAGMA synchronous=NORMAL");
            writer.InTransaction(() => {
                CreateTables(writer);
                writer.Execute($"PRAGMA user_version={StorageVersion}");
            });
            reader = SqliteConnection.Open(path, Sqlite.OpenReadOnly);
            return new HistoryStore(path, writer, reader, announce);
        } catch {
            reader?.Dispose();
            writer.Dispose();
            throw;
        }
    }

    /// The tables, created when absent. Times are milliseconds since 1970;
    /// `host` is the address's host in lower case without a leading `www.`.
    private static void CreateTables(SqliteConnection connection) {
        connection.Execute("CREATE TABLE IF NOT EXISTS place (id INTEGER PRIMARY KEY, space TEXT NOT NULL, url TEXT NOT NULL, "
            + "host TEXT NOT NULL, title TEXT NOT NULL, first_visit INTEGER NOT NULL, last_visit INTEGER NOT NULL, "
            + "visit_count INTEGER NOT NULL, UNIQUE (space, url))");
        connection.Execute("CREATE INDEX IF NOT EXISTS place_recent ON place (space, last_visit DESC)");
        connection.Execute("CREATE INDEX IF NOT EXISTS place_host ON place (space, host)");
        connection.Execute("CREATE TABLE IF NOT EXISTS visit (id INTEGER PRIMARY KEY, place INTEGER NOT NULL, at INTEGER NOT NULL)");
        connection.Execute("CREATE UNIQUE INDEX IF NOT EXISTS visit_place ON visit (place, at)");
        connection.Execute("CREATE INDEX IF NOT EXISTS visit_at ON visit (at)");
        // The Spaces whose session history the store took in once.
        connection.Execute("CREATE TABLE IF NOT EXISTS adopted (space TEXT PRIMARY KEY)");
        // The start of each page's readable text, as it last loaded, zlib-compressed.
        connection.Execute("CREATE TABLE IF NOT EXISTS page_text (place INTEGER PRIMARY KEY, captured_at INTEGER NOT NULL, "
            + "text BLOB NOT NULL)");
        // Each place's title, address and text words, by the place's
        // identity, with accents folded and two- and three-letter prefixes
        // indexed for typing. Contentless: the words are not kept twice.
        connection.Execute("CREATE VIRTUAL TABLE IF NOT EXISTS page_search USING fts5(title, address, text, content='', "
            + "contentless_delete=1, tokenize='unicode61 remove_diacritics 2', prefix='2 3')");
    }

    /// Moves a file that cannot be used aside, with its sidecars, so the next
    /// open starts a new one and the old one stays for a person to look at.
    private static void SetAside(string path) {
        string aside = path + DamagedSuffix;
        if (File.Exists(aside) || Directory.Exists(aside) || SidecarSuffixes.Any(suffix => File.Exists(aside + suffix)))
            aside += "." + Guid.NewGuid().ToString("N");
        foreach (string suffix in (string[])["", .. SidecarSuffixes]) {
            if (!File.Exists(path + suffix)) continue;
            Restrict(path + suffix);
            File.Move(path + suffix, aside + suffix, overwrite: false);
        }
    }

    private static void Restrict(string path) {
        if (!OperatingSystem.IsWindows() && File.Exists(path)) File.SetUnixFileMode(path, OwnerOnly);
    }

    private static StorageFailure Failure(Exception error) => error is StorageException storage ? storage.Reason
        : error is UnauthorizedAccessException ? StorageFailure.ReadOnly : StorageFailure.Unavailable;

    #endregion

    #region Actions - Writing

    /// Queues `write` to run on the worker after every write queued before
    /// it, inside a transaction it may share with them. A write that fails
    /// rolls back its whole batch and retains it for a later write or flush
    /// to retry. A committed batch announces it when a write in it `announces`.
    private void Enqueue(Action write, bool announces = true) {
        lock (queue) {
            if (stopping) throw new Rejected(new StorageUnreadable(StorageFailure.Unavailable));
            pending.Enqueue((write, announces));
            failedWrite = null;
            queued++;
            Monitor.PulseAll(queue);
        }
    }

    /// Waits until every queued write commits, retrying a previously failed
    /// batch once. Refuses with `StorageUnreadable` if the write still fails;
    /// an export must not report success with missing queued history.
    internal void Flush() {
        lock (queue) {
            long target = queued;
            if (failedWrite is not null && !stopping) {
                failedWrite = null;
                Monitor.PulseAll(queue);
            }
            while (done < target) {
                if (failedWrite is { } error) throw new Rejected(new StorageUnreadable(error.Reason));
                if (closed) throw new Rejected(new StorageUnreadable(StorageFailure.Unavailable));
                Monitor.Wait(queue);
            }
        }
    }

    private void Run() {
        List<(Action Write, bool Announces)> batch = [];
        while (TakeBatch(batch)) {
            if (WriteBatch(batch) is not { } changed) continue;
            long announced;
            lock (queue) {
                done += batch.Count;
                announced = changed ? ++revision : 0;
                Monitor.PulseAll(queue);
            }
            batch.Clear();
            if (announced > 0) announce(new StoredHistoryChanged(announced));
        }
    }

    /// Waits until there is something to write and no failed write holds the
    /// queue, or the store stops, then tops `batch` up with pending writes.
    /// False when the worker ends: stopping with nothing to write, or with a
    /// failed write.
    private bool TakeBatch(List<(Action Write, bool Announces)> batch) {
        lock (queue) {
            while ((pending.Count == 0 && batch.Count == 0 || failedWrite is not null) && !stopping) Monitor.Wait(queue);
            if (pending.Count == 0 && batch.Count == 0 || stopping && failedWrite is not null) return false;
            while (pending.Count > 0 && batch.Count < MaximumBatch) batch.Add(pending.Dequeue());
            return true;
        }
    }

    /// Writes `batch` in one transaction and answers whether it changed rows
    /// that announce; null when the write failed, which then holds the queue,
    /// keeps the batch for the retry and is announced.
    private bool? WriteBatch(List<(Action Write, bool Announces)> batch) {
        try {
            long before = writer.TotalChanges;
            writer.InTransaction(() => {
                foreach (var (write, _) in batch) write();
            });
            return writer.TotalChanges != before && batch.Any(write => write.Announces);
        } catch (StorageException error) {
            long unsaved;
            lock (queue) {
                failedWrite = error;
                unsaved = queued - done;
            }
            // Ordinary navigation does not call Flush. Wake the native
            // diagnostic boundary without waiting for another write.
            announce(new HistoryStorageFailed(HistoryStorageOperation.Write, error.Reason, unsaved));
            lock (queue) Monitor.PulseAll(queue);
            return null;
        }
    }

    /// `sql` prepared once on the writer's connection. The worker alone calls it.
    private SqliteStatement Writing(string sql) {
        if (!writing.TryGetValue(sql, out var statement)) writing[sql] = statement = writer.Prepare(sql);
        return statement;
    }

    #endregion

    #region Actions - Reading

    /// What `read` makes of the store, on the connection reads take. A read
    /// failure or closed store is refused rather than reported as empty history.
    private T Read<T>(Func<Func<string, SqliteStatement>, T> read) {
        lock (readGate) {
            if (closed) throw new Rejected(new StorageUnreadable(StorageFailure.Unavailable));
            try {
                return read(sql => {
                    if (!reading.TryGetValue(sql, out var statement)) reading[sql] = statement = reader.Prepare(sql);
                    return statement;
                });
            } catch (StorageException error) {
                announce(new HistoryStorageFailed(HistoryStorageOperation.Read, error.Reason, 0));
                throw new Rejected(new StorageUnreadable(error.Reason));
            }
        }
    }

    #endregion

    #region Actions - Lifetime

    /// Finishes queued work and retries a failed batch once before closing.
    /// A persistent failure closes resources but explicitly reports the number
    /// of queued operations not saved and throws `StorageUnreadable`. It cannot
    /// make unsaved memory durable on a disk that still refuses writes.
    public void Dispose() {
        lock (queue) {
            if (stopping) {
                while (!disposed) Monitor.Wait(queue);
                return;
            }
            stopping = true;
            failedWrite = null;
            Monitor.PulseAll(queue);
        }
        worker.Join();
        lock (readGate) {
            foreach (var statement in reading.Values) statement.Dispose();
            reading.Clear();
            reader.Dispose();
            closed = true;
        }
        foreach (var statement in writing.Values) statement.Dispose();
        writing.Clear();
        writer.Dispose();
        long unsaved;
        StorageFailure reason;
        lock (queue) {
            unsaved = queued - done;
            reason = failedWrite?.Reason ?? StorageFailure.Unavailable;
            disposed = true;
            Monitor.PulseAll(queue);
        }
        if (unsaved == 0) return;
        announce(new HistoryStorageFailed(HistoryStorageOperation.Close, reason, unsaved));
        throw new Rejected(new StorageUnreadable(reason));
    }

    #endregion
}
