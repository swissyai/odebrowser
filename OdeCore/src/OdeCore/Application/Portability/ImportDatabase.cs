using System.Runtime.InteropServices;

namespace OdeCore.Application;

/// A database another browser may hold open while it runs, read from a copy
/// of it and of the files SQLite keeps its state in beside it, opened
/// read-only; the copy is removed afterwards. A copy taken in the middle of a
/// write carries the rollback journal, so SQLite refuses to read it rather
/// than hand out the unfinished transaction.
internal static partial class ImportDatabase {
    #region Static Variables

    /// The files SQLite keeps a database's state in, beside the database: the
    /// log it writes ahead of it and the journal it rolls an unfinished
    /// transaction back from.
    private static readonly string[] CompanionSuffixes = ["-wal", "-journal"];
    /// `copyfile`'s flag to copy a file's data.
    private const uint CopyData = 1 << 3;

    #endregion

    #region Actions - Reading

    /// What `read` makes of the database at `path`, or `fallback` when it is
    /// missing or cannot be copied or opened.
    public static T Read<T>(string path, Func<nint, T> read, T fallback, Action? failed = null) {
        ArgumentNullException.ThrowIfNull(read);
        if (!File.Exists(path)) return fallback;
        DirectoryInfo? copy = null;
        try {
            copy = Directory.CreateTempSubdirectory("ode-import-");
            string database = Path.Combine(copy.FullName, Path.GetFileName(path));
            CopyUnlocked(path, database);
            foreach (string suffix in CompanionSuffixes)
                if (File.Exists(path + suffix)) CopyUnlocked(path + suffix, database + suffix);
            if (Sqlite.sqlite3_open_v2(database, out var connection, Sqlite.OpenReadOnly, null) != Sqlite.Ok) {
                if (connection != 0) Sqlite.sqlite3_close_v2(connection);
                failed?.Invoke();
                return fallback;
            }
            try {
                return read(connection);
            } finally {
                Sqlite.sqlite3_close_v2(connection);
            }
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException
            or ArgumentException) {
            failed?.Invoke();
            return fallback;
        } finally {
            try {
                copy?.Delete(recursive: true);
            } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            }
        }
    }

    /// Copies the file at `source` to `target` with the system's own copy,
    /// which takes no lock. .NET's copy takes an advisory lock first, which a
    /// running browser's hold on its open database refuses, so its history
    /// would read as none.
    private static void CopyUnlocked(string source, string target) {
        if (copyfile(source, target, 0, CopyData) != 0) File.Copy(source, target, overwrite: true);
    }

    [LibraryImport("/usr/lib/libSystem.B.dylib", EntryPoint = "copyfile", StringMarshalling = StringMarshalling.Utf8)]
    private static partial int copyfile(string from, string to, nint state, uint flags);

    #endregion
}
