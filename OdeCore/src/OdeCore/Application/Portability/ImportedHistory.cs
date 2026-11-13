using OdeCore.Contracts;

namespace OdeCore.Application;

/// The history one browser profile kept, as an import reads it from the
/// browser's database: each web address once, without its fragment, with the
/// title of its latest visit, how many visits the browser counted and the
/// time of each visit it still holds. A reader adds the addresses it finds,
/// each under the row identity the browser gave it, then the visits naming
/// those rows. Addresses differing only in their fragment are one, counted
/// together; the one visited last keeps its title.
internal sealed class ImportedHistory {
    #region Static Variables

    /// The most addresses one profile's history brings.
    public const int MaximumAddresses = 500_000;

    /// The most visit times one profile's history brings, all addresses together.
    public const int MaximumVisits = 4_000_000;

    #endregion

    #region Types

    private sealed class Entry(string title, ImportAddress address, DateTimeOffset? lastVisitedAt, long visitCount) {
        public string Title { get; set; } = title;
        public ImportAddress Address { get; } = address;
        public DateTimeOffset? LastVisitedAt { get; set; } = lastVisitedAt;
        public DateTimeOffset? TitledAt { get; set; } = lastVisitedAt;
        public long VisitCount { get; set; } = visitCount;
        public List<DateTimeOffset> Visits { get; } = [];
    }

    #endregion

    #region Variables

    private readonly List<Entry> entries = [];
    private readonly Dictionary<string, Entry> byAddress = new(StringComparer.Ordinal);
    private readonly Dictionary<long, Entry> byRow = [];
    private int visits;
    private int unsupportedAddresses;
    private bool readFailed;
    public bool AddressesOmitted { get; private set; }
    public bool VisitsOmitted { get; private set; }

    #endregion

    #region Actions - Reading

    /// Reads from the temporary database copy, retaining typed failure facts
    /// even when copying or opening fails before a row can be read.
    public static IReadOnlyList<SessionHistoryEntry> Read(string path, Func<nint, ImportedHistory> reader,
        ICollection<Rejection>? problems) {
        var unavailable = new ImportedHistory();
        return ImportDatabase.Read(path, reader, unavailable, unavailable.Failed).Entries(problems);
    }

    public void Failed() => readFailed = true;

    public void Finished(int status) {
        if (status != Sqlite.Done) Failed();
    }

    /// The address the browser keeps in row `row`, spelled `url`, titled
    /// `title`, last visited at `lastVisitedAt` when the browser keeps that
    /// beside its visits, and counted `visitCount` times. An address that is
    /// not a web page, or one past the most addresses brought, is left out.
    public void Add(long row, string? url, string title, DateTimeOffset? lastVisitedAt, long visitCount) {
        if (ImportAddress.Read(url, removesFragment: true) is not { } address) {
            unsupportedAddresses++;
            return;
        }
        long counted = Math.Clamp(visitCount, 0, BrowserDataHistoryEntry.MaximumVisitCount);
        if (byAddress.TryGetValue(address.Spelling, out var same)) {
            same.VisitCount = Math.Min(same.VisitCount + counted, BrowserDataHistoryEntry.MaximumVisitCount);
            if (lastVisitedAt > same.LastVisitedAt) {
                same.LastVisitedAt = lastVisitedAt;
                if (title.Length > 0) (same.Title, same.TitledAt) = (title, lastVisitedAt);
            }
            byRow[row] = same;
            return;
        }
        if (entries.Count >= MaximumAddresses) {
            AddressesOmitted = true;
            return;
        }
        var entry = new Entry(title, address, lastVisitedAt, counted);
        entries.Add(entry);
        byAddress[address.Spelling] = entry;
        byRow[row] = entry;
    }

    /// A visit at `at` to the address in row `row`, which titled it `title`
    /// when the browser keeps a title with each visit. A visit to a row left
    /// out, or past the most visits brought, is left out.
    public void Visit(long row, DateTimeOffset? at, string? title = null) {
        if (at is not { } time || !byRow.TryGetValue(row, out var entry)) return;
        if (visits >= MaximumVisits) {
            VisitsOmitted = true;
            return;
        }
        entry.Visits.Add(time);
        visits++;
        if (entry.LastVisitedAt is not { } last || time > last) entry.LastVisitedAt = time;
        if (!string.IsNullOrEmpty(title) && (entry.TitledAt is not { } titled || time >= titled)) (entry.Title, entry.TitledAt) = (title, time);
    }

    /// The history read, the most recently visited first: each address
    /// visited at a known time, counted at least once for each visit it
    /// holds.
    public IReadOnlyList<SessionHistoryEntry> Entries(ICollection<Rejection>? problems = null) {
        if (AddressesOmitted) problems?.Add(new HistoryAddressesOverLimit());
        if (VisitsOmitted) problems?.Add(new HistoryVisitsOverLimit());
        if (readFailed) problems?.Add(new HistoryReadFailed());
        if (unsupportedAddresses > 0) problems?.Add(new HistoryAddressesUnsupported(unsupportedAddresses));
        return [.. entries
            .Where(entry => entry.LastVisitedAt is not null)
            .Select(entry => new SessionHistoryEntry(entry.Title, entry.Address, entry.LastVisitedAt!.Value,
                Math.Max(entry.VisitCount, entry.Visits.Count), [.. entry.Visits.Order()]))
            .OrderByDescending(entry => entry.LastVisitedAt)];
    }

    #endregion
}
