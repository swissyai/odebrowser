using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

/// Reads other browsers' data without the app lock. Each read owns its full
/// history until an import consumes it, the caller cancels it, or the core
/// closes. Accepted reads are never expired or evicted for another read.
internal sealed class Portability(IReadOnlyList<ImportSpaceNames>? names, IClock clock, IIdSource ids) {
    #region Static Variables

    internal const int MaximumPendingReads = 4;
    private const int MaximumPendingAddresses = ImportedHistory.MaximumAddresses * 2;
    private const int MaximumPendingVisits = ImportedHistory.MaximumVisits * 2;

    #endregion

    #region Types

    private sealed class Read {
        public Dictionary<Guid, IReadOnlyList<ImportedPlace>> Histories { get; set; } = [];
        public HashSet<Guid> Spaces { get; set; } = [];
        public bool Reading { get; set; }
        public bool Ready { get; set; }
        public bool Canceled { get; set; }
    }

    #endregion

    #region Variables

    private readonly Dictionary<Guid, Read> reads = [];
    private readonly Lock histories = new();
    private bool closed;

    internal IClock Clock => clock;
    internal IIdSource Ids => ids;
    internal int PendingReads { get { lock (histories) return reads.Count; } }

    #endregion

    #region Actions - Queries

    public ExportedDocument Export(SessionState session, ExportFormat format, HistoryStore? history) =>
        ExportWriter.Of(format).Write(session, clock.Now, history);

    /// Reserves bounded ownership before detached work starts, so cancellation
    /// before, during and after the read refers to the same lifetime.
    internal Guid PrepareRead() {
        lock (histories) {
            if (closed) throw new Rejected(new ImportReadUnavailable());
            if (reads.Count >= MaximumPendingReads) throw new Rejected(new ImportReadLimitReached());
            var id = Guid.NewGuid();
            reads.Add(id, new Read());
            return id;
        }
    }

    internal void StartRead(Guid id) {
        lock (histories) {
            if (!reads.TryGetValue(id, out var read) || read.Canceled || read.Reading || read.Ready)
                throw new Rejected(new ImportReadUnavailable());
            read.Reading = true;
        }
    }

    /// Keeps this read only. A canceled detached read still owns its slot
    /// until it finishes, but can never publish or replace another read.
    internal ImportedSpaces KeepRead(Guid id, ImportedSpaces result,
        IReadOnlyDictionary<Guid, IReadOnlyList<SessionHistoryEntry>> readHistories) {
        lock (histories) {
            if (!reads.TryGetValue(id, out var pending) || pending.Canceled || closed)
                throw new Rejected(new ImportReadUnavailable());
        }
        var places = readHistories.ToDictionary(pair => pair.Key, pair => SessionHistoryEntry.Places(pair.Value));
        lock (histories) {
            if (!reads.TryGetValue(id, out var read) || read.Canceled || closed)
                throw new Rejected(new ImportReadUnavailable());
            long addresses = places.Values.Sum(entries => (long)entries.Count);
            long visits = places.Values.Sum(entries => entries.Sum(place => (long)place.Visits.Count));
            foreach (var other in reads.Values.Where(other => other.Ready)) {
                addresses += other.Histories.Values.Sum(entries => (long)entries.Count);
                visits += other.Histories.Values.Sum(entries => entries.Sum(place => (long)place.Visits.Count));
            }
            if (addresses > MaximumPendingAddresses || visits > MaximumPendingVisits)
                throw new Rejected(new ImportReadLimitReached());
            read.Histories = places;
            read.Spaces = result.Spaces.Select(space => space.Id).ToHashSet();
            read.Reading = false;
            read.Ready = true;
            return result with { Spaces = [.. result.Spaces.Select(space => space with { ImportReadId = id })] };
        }
    }

    internal void FailedRead(Guid id) {
        lock (histories) reads.Remove(id);
    }

    internal bool DiscardRead(Guid id) {
        lock (histories) {
            if (!reads.TryGetValue(id, out var read)) return false;
            if (read.Reading) read.Canceled = true;
            else reads.Remove(id);
            return true;
        }
    }

    /// Validates every read before any session edit. Holds ownership through
    /// commit, and releases the entire read on success or refusal, including
    /// excluded Spaces. Reusing an exhausted/canceled result is explicit loss,
    /// never permission to import its truncated session projection instead.
    internal void ImportReads(IEnumerable<SpaceState> spaces, Action commit) {
        var inputs = spaces.ToArray();
        var owned = inputs.Where(space => space.ImportReadId is not null).GroupBy(space => space.ImportReadId!.Value).ToArray();
        lock (histories) {
            try {
                foreach (var group in owned)
                    if (!reads.TryGetValue(group.Key, out var read) || !read.Ready || read.Canceled
                        || group.Any(space => !read.Spaces.Contains(space.Id)))
                        throw new Rejected(new ImportReadUnavailable());
                commit();
            } finally {
                foreach (var group in owned) DiscardRead(group.Key);
            }
        }
    }

    internal IReadOnlyList<ImportedPlace>? TakeReadHistory(Guid spaceId) {
        lock (histories) {
            foreach (var read in reads.Values)
                if (read.Ready && !read.Canceled && read.Histories.Remove(spaceId, out var places)) return places;
            return null;
        }
    }

    internal void Close() {
        lock (histories) {
            closed = true;
            reads.Clear();
        }
    }

    internal ImportSpaceNames Names(ImportSource source) =>
        names?.FirstOrDefault(entry => entry.Source == source)
        ?? new(source, source.SpaceName ?? source.Title, source.NumberedSpaceName ?? source.Title);

    #endregion
}
