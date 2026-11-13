namespace OdeCore.Application;

/// A tab another browser archived for a Space: the page it showed and when
/// the browser archived it.
internal sealed record SessionArchivedTab(string Title, ImportAddress Address, DateTimeOffset ArchivedAt);
