namespace OdeCore.Application;

/// An address in another browser's history, without its fragment: the title
/// it showed, when it was last visited, how many times it was, and the time
/// of each visit the browser still keeps, oldest first.
internal sealed record SessionHistoryEntry(string Title, ImportAddress Address, DateTimeOffset LastVisitedAt, long VisitCount,
    IReadOnlyList<DateTimeOffset>? Visits = null) {
    #region Actions - Places

    /// Every address of `entries` as the history kept beside the session
    /// takes it: each once, its visits and counts together, titled as on its
    /// latest visit; an address whose title a Space would not keep is left
    /// out, as a Space's own history leaves it out.
    public static IReadOnlyList<ImportedPlace> Places(IEnumerable<SessionHistoryEntry> entries) {
        ArgumentNullException.ThrowIfNull(entries);
        Dictionary<string, (string Title, DateTimeOffset First, DateTimeOffset Last, long Count, List<DateTimeOffset> Visits)> merged =
            new(StringComparer.Ordinal);
        List<string> order = [];
        foreach (var entry in entries) {
            string url = entry.Address.Spelling;
            if (ImportText.Bounded(entry.Title, entry.Address.Host, ImportText.MaximumTitle) is not { } title
                || !ImportAddress.TryReadStored(url, removesFragment: true, out var stored) || stored is null) continue;
            var visits = entry.Visits ?? [];
            var first = visits.Count > 0 && visits[0] < entry.LastVisitedAt ? visits[0] : entry.LastVisitedAt;
            if (!merged.TryGetValue(url, out var held)) {
                merged[url] = (title, first, entry.LastVisitedAt, entry.VisitCount, [.. visits]);
                order.Add(url);
                continue;
            }
            held.Visits.AddRange(visits);
            bool later = entry.LastVisitedAt > held.Last;
            merged[url] = (later ? title : held.Title, first < held.First ? first : held.First, later ? entry.LastVisitedAt : held.Last,
                Math.Min(held.Count + entry.VisitCount, BrowserDataHistoryEntry.MaximumVisitCount), held.Visits);
        }
        return [.. order.Select(url => {
            var place = merged[url];
            return new ImportedPlace(url, place.Title, place.First, place.Last, place.Count, [.. place.Visits.Distinct().Order()]);
        })];
    }

    #endregion
}
