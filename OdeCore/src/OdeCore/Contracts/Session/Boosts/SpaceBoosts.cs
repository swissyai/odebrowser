namespace OdeCore.Contracts;

/// The Boosts a Space keeps, at most one for each site, in the order they were
/// first made.
public sealed record SpaceBoosts(IReadOnlyList<SiteBoost> Sites) {
    #region Static Variables

    /// The most Boosts one Space keeps.
    public const int MaximumBoosts = 500;

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SiteBoost> Sites {
        get;
        init => field = [.. value];
    } = [.. Sites];

    #endregion

    #region Actions - Lookup

    /// The Boost for `site`, as `SiteBoost.SiteOf` spells it, or null.
    public SiteBoost? For(string site) => Sites.FirstOrDefault(boost => boost.Site == site);

    #endregion

    #region Actions - Editing

    /// The Boosts with `boost`, which must be normalized, in place of the one
    /// for its site, or after the others when there was none. Throws
    /// `Rejected` with `BoostLimitReached` when that would keep more than
    /// `MaximumBoosts`.
    public SpaceBoosts Setting(SiteBoost boost) {
        ArgumentNullException.ThrowIfNull(boost);
        int index = Sites.Select(kept => kept.Site).ToList().IndexOf(boost.Site);
        if (index >= 0) return this with { Sites = [.. Sites.Take(index), boost, .. Sites.Skip(index + 1)] };
        return Sites.Count >= MaximumBoosts
            ? throw new Rejected(new BoostLimitReached(MaximumBoosts)) : this with { Sites = [.. Sites, boost] };
    }

    /// The Boosts without the one for `site`, or null when none is left.
    public SpaceBoosts? Removing(string site) {
        var kept = Sites.Where(boost => boost.Site != site).ToArray();
        return kept.Length == 0 ? null : this with { Sites = kept };
    }

    /// The Boosts `boosts` holds that a Space keeps: each normalized, the
    /// first for each site, within the limit; null when none is.
    public static SpaceBoosts? Kept(IEnumerable<SiteBoost?> boosts) {
        ArgumentNullException.ThrowIfNull(boosts);
        var kept = boosts.Select(boost => boost?.Normalized()).OfType<SiteBoost>().DistinctBy(boost => boost.Site, StringComparer.Ordinal)
            .Take(MaximumBoosts).ToArray();
        return kept.Length == 0 ? null : new(kept);
    }

    #endregion

    #region Actions - Equality

    public bool Equals(SpaceBoosts? other) => other is not null && Sites.SequenceEqual(other.Sites);

    public override int GetHashCode() => Sites.Aggregate(Sites.Count, (hash, boost) => HashCode.Combine(hash, boost));

    #endregion
}
