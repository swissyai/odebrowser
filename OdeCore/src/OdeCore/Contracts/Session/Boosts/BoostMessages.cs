namespace OdeCore.Contracts;

#region Rejections

/// A Boost names no site whose pages it could restyle.
public sealed record InvalidBoostSite() : Rejection;

/// The Space keeps `Limit` Boosts and has none for this site.
public sealed record BoostLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "A Space keeps up to %lld Boosts.";

    #endregion
}

#endregion
