using System.Text.Json.Nodes;

using OdeCore.Contracts;

namespace OdeCore.Application;

/// A tab in a Space's archive as an Ode browser-data file keeps it, with the
/// reason it arrived there spelled as the reason's name.
internal sealed record BrowserDataArchivedTab(BrowserDataTab Tab, DateTimeOffset ArchivedAt, ArchiveReason Reason) {
    #region Actions - Reading

    public static BrowserDataArchivedTab Read(BrowserDataValue value) => new(BrowserDataTab.Read(value.Nested("tab")),
        value.Date("archivedAt"), ArchiveReason.Named(value.Text("reason")) ?? throw BrowserDataValue.Invalid());

    /// The archived tab a Space keeps, with a new identity. Throws
    /// `ArchiveInvalid` for a tab a Space would not keep, or one saved or
    /// pinned, which the archive never holds.
    public ArchivedTabState Materialize(Guid id) {
        var tab = Tab.Materialize(id, new Dictionary<Guid, Guid>(), new Dictionary<Guid, Guid>());
        if (tab.Placement.IsDurable) throw BrowserDataValue.Invalid();
        return new(tab, ArchivedAt, Reason);
    }

    #endregion

    #region Actions - Writing

    public static BrowserDataArchivedTab From(ArchivedTabState archived) {
        ArgumentNullException.ThrowIfNull(archived);
        // An archived tab nests under nothing a file could name.
        return new(BrowserDataTab.From(archived.Tab with { ParentTabId = null, CollapsesNestedTabs = false }), archived.ArchivedAt,
            archived.Reason);
    }

    public JsonObject Write() => new() {
        ["tab"] = Tab.Write(),
        ["archivedAt"] = ImportDate.UnixMilliseconds(ArchivedAt),
        ["reason"] = Reason.Name
    };

    #endregion
}
