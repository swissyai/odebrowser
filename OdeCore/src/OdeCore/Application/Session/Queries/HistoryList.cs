using System.Globalization;

using OdeCore.Application;

namespace OdeCore.Contracts;

/// The history of `SpaceId`, newest first: every address this device keeps
/// for it, last visited before `Before` when that is set, at most `Limit` of
/// them. `BeforeUrl` continues within addresses sharing that visit time.
/// With `Text`, the addresses whose title or address hold its words, best
/// first, the last word as the start of one. A workspace that keeps nothing,
/// such as a private window's, answers from the history its session holds.
///
/// Refused with `UnknownSpace` for a Space the workspace does not hold or is
/// deleting, and `SpaceLocked` while this process may not show it.
public sealed record HistoryList(Guid WorkspaceId, Guid SpaceId, string Text, DateTimeOffset? Before, int Limit, string? BeforeUrl = null)
    : Query<HistoryPlaces> {
    #region Static Variables

    /// The most places one answer brings.
    public const int MaximumLimit = 5_000;

    #endregion

    #region Variables

    /// Only finding the Space holds the lock; the store has a reader of its own.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override HistoryPlaces Answer(OdeApp app) {
        (SpaceState Space, HistoryStore? Store) readable;
        lock (app.Gate) readable = app.Device.Workspace(WorkspaceId).ReadableHistory(SpaceId);
        int limit = Math.Clamp(Limit, 1, MaximumLimit);
        string text = Text.Trim();
        if (readable.Store is not { } store) return Kept(readable.Space, text, limit);
        if (text.Length == 0) return store.Places(SpaceId, Before, limit, BeforeUrl);
        return new(store.Matching(SpaceId, text, limit), HasMore: false);
    }

    /// The session's own history of `space`, as `HistoryList` describes it,
    /// matching `text` anywhere in a title or address, ignoring case and accents.
    private HistoryPlaces Kept(SpaceState space, string text, int limit) {
        var compare = CultureInfo.InvariantCulture.CompareInfo;
        const CompareOptions Loose = CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace;
        var places = space.History
            .OrderByDescending(entry => entry.LastVisitedAt).ThenByDescending(entry => entry.Url, StringComparer.Ordinal)
            .Where(entry => Before is not { } before || entry.LastVisitedAt < before
                || entry.LastVisitedAt == before && BeforeUrl is { } url && string.CompareOrdinal(entry.Url, url) < 0)
            .Where(entry => text.Length == 0 || compare.IndexOf(entry.Title, text, Loose) >= 0 || compare.IndexOf(entry.Url, text, Loose) >= 0)
            .Take(limit + 1)
            .Select(entry => new HistoryPlace(entry.Url, entry.Title, entry.FirstVisitedAt, entry.LastVisitedAt, entry.VisitCount))
            .ToList();
        bool more = places.Count > limit;
        return new(more ? places[..limit] : places, more);
    }

    #endregion
}
