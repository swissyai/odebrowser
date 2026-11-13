using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// When the session was last swept, and the retention each Space had then.
    internal sealed record SweepMark(DateTimeOffset At, IReadOnlyList<SpaceRetention> Retention) {
        #region Actions - Throttling

        /// Whether a sweep at `now` of `session` would repeat this one: it comes
        /// less than `MinimumSweepSpacing` later, and no Space's retention
        /// changed. A clock that went backwards never holds a sweep back.
        public bool Covers(DateTimeOffset now, SessionState session) =>
            now >= At && now - At < MinimumSweepSpacing && Retention.SequenceEqual(SpaceRetention.Of(session));

        #endregion
    }

    /// What a Space keeps and for how long.
    internal sealed record SpaceRetention(Guid SpaceId, CurrentTabCleanup Cleanup, DataRetentionPreferences Records) {
        #region Actions - Reading

        public static IReadOnlyList<SpaceRetention> Of(SessionState session) => [.. session.Spaces.Select(space =>
            new SpaceRetention(space.Id, space.Settings.BrowsingPreferences.CurrentTabCleanup, space.Settings.BrowsingPreferences.DataRetention))];

        #endregion
    }

    #endregion

    #region Variables

    /// The shortest gap between two sweeps of one session. Windows becoming
    /// active together, or an activation landing on a periodic sweep, sweep once.
    private static readonly TimeSpan MinimumSweepSpacing = TimeSpan.FromMinutes(1);

    /// The last sweep this session ran; null until it runs one.
    private SweepMark? lastSweep;

    /// The last sweep this session ran, which a sweep it would repeat skips.
    internal SweepMark? LastSweep => lastSweep;

    #endregion

    #region Actions - History

    /// The Space `spaceId` names as a search over it reads it, with the
    /// history of its whole group, and the history this session keeps beside
    /// its file, or none for a session that keeps nothing. Throws `Rejected`
    /// with `UnknownSpace` for a Space the session does not hold or one being
    /// deleted, and `SpaceLocked` for one this process may not show.
    internal (SpaceState Space, HistoryStore? Store) ReadableHistory(Guid spaceId) {
        lock (Gate) {
            var space = session.Space(spaceId);
            if (space is null || session.PendingDeletion(spaceId) is not null) throw new Rejected(new UnknownSpace(spaceId));
            if (IsLockedUnderGate(space)) throw new Rejected(new SpaceLocked(spaceId));
            return (session.Searched(space), History);
        }
    }

    internal SpaceState WithoutHistory(SpaceState space, Func<HistoryEntryState, bool> removes) => space.WithoutHistory(removes);

    internal SpaceState WithoutHistory(SpaceState space, Func<HistoryEntryState, int, bool> removes) => space.WithoutHistory(removes);

    #endregion

    #region Actions - Retention

    /// The tabs cleanup keeps open in this workspace however long they went
    /// unused: those its windows show or its saved windows will show, those
    /// whose pages run media, such as a video playing in Picture in Picture or
    /// a screen being shared, and those an agent uses.
    internal IReadOnlySet<Guid>? TabsCleanupKeeps(SessionTurn turn) {
        var shown = Device?.ShownTabs(WorkspaceId);
        var media = turn.Pages?.TabsRunningMedia(WorkspaceId);
        var agents = Device?.AgentTabs;
        IEnumerable<Guid>? kept = null;
        foreach (var set in new[] { shown, media, agents }) {
            if (set is { Count: > 0 }) kept = kept is null ? set : kept.Union(set);
        }
        return kept?.ToHashSet() ?? shown;
    }

    /// What applying the retention of `spaces` at `now` removes from the
    /// history kept beside the session: each visit older than its Space keeps
    /// history, and each address left with none.
    internal static Action<HistoryStore> ExpiringHistory(IReadOnlyList<SpaceState> spaces, DateTimeOffset now) => store => {
        foreach (var space in spaces)
            if (space.Settings.BrowsingPreferences.DataRetention.History.Lifetime is { } lifetime) store.Expire(space.Id, now - lifetime);
    };

    #endregion

    #region Actions - Dates

    /// The dates as the stored format's seconds, which the removal policies read.
    internal double[] Seconds(IEnumerable<DateTimeOffset> dates) => dates.Select(StoredSessionCodec.Seconds).ToArray();

    #endregion
}
