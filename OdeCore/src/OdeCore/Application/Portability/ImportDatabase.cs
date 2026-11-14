using System.ComponentModel;
using System.Runtime.InteropServices;

using Microsoft.Win32.SafeHandles;

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
    /// Linux's O_CLOEXEC; O_RDONLY is zero.
    private const int LinuxReadOnlyCloseOnExec = 0x80000;

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

    /// Copies only the source's bytes, without taking a Unix advisory lock
    /// that a running browser's hold on its database could refuse. macOS
    /// keeps its native copy; Linux opens a read-only descriptor directly,
    /// because managed path-based opens take a shared advisory lock there.
    private static void CopyUnlocked(string source, string target) {
        if (OperatingSystem.IsMacOS()) {
            if (copyfile(source, target, 0, CopyData) != 0) File.Copy(source, target, overwrite: true);
            return;
        }
        using var handle = OperatingSystem.IsLinux()
            ? OpenLinuxReadOnly(source)
            : File.OpenHandle(source, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var input = new FileStream(handle, FileAccess.Read);
        using var output = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None);
        input.CopyTo(output);
    }

    private static SafeFileHandle OpenLinuxReadOnly(string source) {
        // No creation, mutation or advisory locking of the source.
        int descriptor = open(source, LinuxReadOnlyCloseOnExec);
        if (descriptor < 0)
            throw new IOException("Unable to open the import source.", new Win32Exception(Marshal.GetLastPInvokeError()));
        return new SafeFileHandle(descriptor, ownsHandle: true);
    }

    [LibraryImport("/usr/lib/libSystem.B.dylib", EntryPoint = "copyfile", StringMarshalling = StringMarshalling.Utf8)]
    private static partial int copyfile(string from, string to, nint state, uint flags);

    [LibraryImport("libc", EntryPoint = "open", SetLastError = true, StringMarshalling = StringMarshalling.Utf8)]
    private static partial int open(string path, int flags);

    #endregion
}
