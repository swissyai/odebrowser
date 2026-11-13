namespace OdeCore.Contracts;

/// <summary>
/// Whether hovering a pinned or saved tab shows a preview of what its site
/// holds, such as a mail site's unread messages or a calendar's next events,
/// and the sites whose previews the person turned off, each spelled as
/// <see cref="SiteBoost.SiteOf"/> spells a site. A preview is read from the
/// tab's own page and never kept; this device keeps only these choices,
/// among its app-wide preferences, and never syncs them.
/// </summary>
public sealed record TabPreviewPreferences(bool ShowsPreviews, IReadOnlyList<string> SitesWithoutPreviews) {
    #region Static Variables

    /// The most sites a person may turn previews off for.
    public const int MaximumSites = 64;

    /// What a person who never chose has: previews on for every site.
    public static TabPreviewPreferences Default { get; } = new(ShowsPreviews: true, SitesWithoutPreviews: []);

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<string> SitesWithoutPreviews {
        get;
        init => field = [.. value];
    } = [.. SitesWithoutPreviews];

    #endregion

    #region Actions - Restoring

    /// These preferences with each site spelled as a site and named once, in
    /// ordinal order, at most <see cref="MaximumSites"/> of them; a name that
    /// spells no site is left out.
    public TabPreviewPreferences Restored() => this with {
        SitesWithoutPreviews = [.. SitesWithoutPreviews.Select(SiteBoost.SiteOf).OfType<string>().Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal).Take(MaximumSites)]
    };

    #endregion

    #region Actions - Equality

    public bool Equals(TabPreviewPreferences? other) => other is not null
        && ShowsPreviews == other.ShowsPreviews
        && SitesWithoutPreviews.SequenceEqual(other.SitesWithoutPreviews);

    public override int GetHashCode() => HashCode.Combine(ShowsPreviews, SitesWithoutPreviews.Count);

    #endregion
}
