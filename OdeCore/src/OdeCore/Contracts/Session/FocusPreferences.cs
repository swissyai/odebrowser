namespace OdeCore.Contracts;

#region Types

/// <summary>
/// A daily time limit for one site, spelled as <see cref="SiteBoost.SiteOf"/>
/// spells a site, in minutes.
/// </summary>
public sealed record SiteTimeLimit(string Site, int MinutesPerDay);

#endregion

/// <summary>
/// Focus: whether the feeds and recommendations of the sites Ode knows how to
/// quiet are hidden, and the sites the person gave a daily time limit. This
/// device keeps these choices among its app-wide preferences and never syncs
/// them; the time spent on a site never leaves the Mac.
/// </summary>
public sealed record FocusPreferences(bool HidesFeeds, IReadOnlyList<SiteTimeLimit> Limits) {
    #region Static Variables

    /// The most sites a person may limit.
    public const int MaximumLimits = 64;
    public const int MinimumMinutes = 1;
    /// A whole day.
    public const int MaximumMinutes = 1_440;

    /// What a person who never chose has: feeds shown and no limits.
    public static FocusPreferences Default { get; } = new(HidesFeeds: false, Limits: []);

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SiteTimeLimit> Limits {
        get;
        init => field = [.. value];
    } = [.. Limits];

    #endregion

    #region Actions - Limits

    /// The daily limit for `site`, or null when it has none.
    public SiteTimeLimit? LimitFor(string? site) => site is null ? null : Limits.FirstOrDefault(limit => limit.Site == site);

    /// These preferences with `site` limited to `minutes` a day, or without a
    /// limit for it when `minutes` is null.
    public FocusPreferences Limiting(string site, int? minutes) => (this with {
        Limits = [.. Limits.Where(limit => limit.Site != site), .. minutes is { } kept ? [new SiteTimeLimit(site, kept)] : Array.Empty<SiteTimeLimit>()]
    }).Restored();

    #endregion

    #region Actions - Restoring

    /// These preferences with each limit's site spelled as a site and named
    /// once, the last one for a site kept, its minutes within a day, in
    /// ordinal order of their sites, at most <see cref="MaximumLimits"/> of
    /// them; a limit whose name spells no site is left out.
    public FocusPreferences Restored() => this with {
        Limits = [.. Limits
            .Select(limit => SiteBoost.SiteOf(limit.Site) is { } site
                ? new SiteTimeLimit(site, Math.Clamp(limit.MinutesPerDay, MinimumMinutes, MaximumMinutes)) : null)
            .OfType<SiteTimeLimit>()
            .GroupBy(limit => limit.Site, StringComparer.Ordinal).Select(group => group.Last())
            .OrderBy(limit => limit.Site, StringComparer.Ordinal).Take(MaximumLimits)]
    };

    #endregion

    #region Actions - Equality

    public bool Equals(FocusPreferences? other) => other is not null
        && HidesFeeds == other.HidesFeeds
        && Limits.SequenceEqual(other.Limits);

    public override int GetHashCode() => HashCode.Combine(HidesFeeds, Limits.Count);

    #endregion
}
