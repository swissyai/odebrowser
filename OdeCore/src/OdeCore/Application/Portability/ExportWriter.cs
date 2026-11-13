using OdeCore.Contracts;

namespace OdeCore.Application;

/// How the core writes each file an export makes, for the `ExportFormat` the
/// platform names.
internal sealed class ExportWriter {
    #region Static Variables

    public static readonly ExportWriter BrowserData = new(ExportFormat.BrowserData,
        (spaces, now, _) => BrowserDataFile.Write(spaces.Select(BrowserDataSpace.From), now));
    public static readonly ExportWriter Bookmarks = new(ExportFormat.Bookmarks, (spaces, now, _) => BookmarkFile.Write(spaces, now));
    public static readonly ExportWriter History = new(ExportFormat.History, HistoryLines.Write);

    public static IReadOnlyList<ExportWriter> All { get; } = [BrowserData, Bookmarks, History];

    #endregion

    #region Variables

    public ExportFormat Format { get; }

    /// Writes the file of the Spaces at a time, reading the history kept
    /// beside the session where the workspace keeps one.
    private readonly Func<IReadOnlyList<SpaceState>, DateTimeOffset, HistoryStore?, byte[]> write;

    #endregion

    #region Constructors

    private ExportWriter(ExportFormat format, Func<IReadOnlyList<SpaceState>, DateTimeOffset, HistoryStore?, byte[]> write) {
        Format = format;
        this.write = write;
    }

    #endregion

    #region Actions - Writing

    public static ExportWriter Of(ExportFormat format) => All.First(writer => writer.Format == format);

    /// The file of `session`'s Spaces, exported at `now`, with the history
    /// `history` keeps beside it, where the workspace keeps one.
    public ExportedDocument Write(SessionState session, DateTimeOffset now, HistoryStore? history) {
        ArgumentNullException.ThrowIfNull(session);
        return new(write(session.Spaces, now, history), Format);
    }

    #endregion
}
