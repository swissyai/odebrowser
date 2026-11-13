namespace OdeCore.Contracts;

#region Models

/// One address of a Space's history as this device keeps it: its title, its
/// first and latest visit and how many visits it counts.
public sealed record HistoryPlace(string Url, string Title, DateTimeOffset FirstVisitedAt, DateTimeOffset LastVisitedAt, int VisitCount);

/// A Space's history newest first, as far as one answer goes: `Places`, and
/// whether older places follow, `HasMore`, which a request for those before
/// the last one's latest visit and address brings.
public sealed record HistoryPlaces(IReadOnlyList<HistoryPlace> Places, bool HasMore);

/// A synchronous history flush or close outcome, so even a final failed
/// write has a live host to record its exact reason and queued-operation count.
public sealed record HistoryStorageResult(HistoryStorageFailed? Failure);

/// The history operation that could not finish. These carry no browsing data.
public enum HistoryStorageOperation { Open, Recovery, Write, Read, PageText, Close }

#endregion

#region Changes

/// The history this device keeps beside the session changed: a visit, a
/// title, a removal or an import reached its file. `Revision` grows with each
/// change, so a list of it reads again when it moves.
public sealed record StoredHistoryChanged(long Revision) : Change;

/// A history-only storage failure, not a failure of the session save. Pending
/// writes stay in memory for retry until close; `UnsavedWrites` counts queued
/// operations, not visits (an import operation can contain many addresses).
/// No address, title, page text, path or SQLite message crosses this boundary.
public sealed record HistoryStorageFailed(HistoryStorageOperation Operation, StorageFailure Reason, long UnsavedWrites) : Change;

#endregion
