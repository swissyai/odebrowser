using System.Text.Json;

using OdeCore.Contracts;

namespace OdeCore.Application;

/// The tabs Arc archived, `StorableArchiveItems.json` beside its sidebar: a
/// list alternating identities and items, each item the sidebar item Arc
/// archived, when, in seconds since 2001, and the Space it came from.
internal static class ArcArchive {
    #region Static Variables

    private const string FileName = "StorableArchiveItems.json";

    /// The largest archive an import reads.
    private const long MaximumBytes = InstalledBrowser.MaximumSessionBytes;

    #endregion

    #region Actions - Reading

    /// Each web page Arc archived in the folder `folder`, with the identity of
    /// the Space it came from, where Arc names one, and dated `importedAt`
    /// where Arc gave no time. None when the archive is missing or cannot be
    /// read.
    public static IReadOnlyList<(string? Space, SessionArchivedTab Tab)> Read(string folder, DateTimeOffset importedAt) {
        byte[] contents;
        try {
            contents = ImportFile.Read(Path.Combine(folder, FileName), MaximumBytes, new FileUnreadable(), new FileUnreadable());
        } catch (Rejected) {
            return [];
        }
        using var document = ImportJson.Parse(contents);
        if (document is null) return [];
        List<(string?, SessionArchivedTab)> archived = [];
        foreach (var item in ImportJson.Array(ImportJson.Member(document.RootElement, "items")) ?? []) {
            if (item.ValueKind != JsonValueKind.Object) continue;
            var sidebarItem = ImportJson.Member(item, "sidebarItem");
            var tab = ImportJson.Member(ImportJson.Member(sidebarItem, "data"), "tab");
            if (ImportAddress.Read(ImportJson.Text(ImportJson.Member(tab, "savedURL"))) is not { } address) continue;
            string title = ImportJson.Text(ImportJson.Member(tab, "savedTitle")) ?? ImportJson.Text(ImportJson.Member(sidebarItem, "title")) ?? "";
            var time = ImportJson.Number(ImportJson.Member(item, "archivedAt")) is { } seconds ? ImportDate.FromReferenceSeconds(seconds) : null;
            string? space = ImportJson.Text(ImportJson.Member(ImportJson.Member(ImportJson.Member(item, "source"), "space"), "_0"));
            archived.Add((space, new SessionArchivedTab(title, address, time ?? importedAt)));
        }
        return archived;
    }

    #endregion
}
