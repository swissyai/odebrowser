namespace OdeCore.Domain;

/// What breaks a tie between rows that score alike, tried in this order: a
/// place the person ever typed, the match nearest the start of the address,
/// more typed uses, a site's front page over a deeper page, more visits, the
/// later use, then the title. It also names the host and core title a row
/// shares with duplicates of the same page under another address.
internal sealed record PaletteOrder(bool Typed, int Offset, int TypedUses, bool IsHostOnly, int Visits, DateTimeOffset? LastUsed, string Title,
    string? Host, string? Core) {
    #region Static Variables

    /// The order of a row that is no page, which ties break by title alone.
    public static readonly PaletteOrder None = new(Typed: false, int.MaxValue, TypedUses: 0, IsHostOnly: false, Visits: 0, LastUsed: null, "",
        Host: null, Core: null);

    /// Best first: by score, then down the ladder.
    public static readonly IComparer<PaletteCandidate> Comparer = Comparer<PaletteCandidate>.Create(Compare);

    #endregion

    #region Variables

    /// The host and core title together, which duplicates of a page share.
    public string? Duplicate => Host is null || Core is null ? null : $"{Host}|{Core.ToLowerInvariant()}";

    #endregion

    #region Actions - Comparing

    private static int Compare(PaletteCandidate left, PaletteCandidate right) {
        int result = right.Score.CompareTo(left.Score);
        if (result != 0) return result;
        var mine = left.Order ?? None;
        var theirs = right.Order ?? None;
        result = theirs.Typed.CompareTo(mine.Typed);
        if (result != 0) return result;
        result = mine.Offset.CompareTo(theirs.Offset);
        if (result != 0) return result;
        result = theirs.TypedUses.CompareTo(mine.TypedUses);
        if (result != 0) return result;
        result = theirs.IsHostOnly.CompareTo(mine.IsHostOnly);
        if (result != 0) return result;
        result = theirs.Visits.CompareTo(mine.Visits);
        if (result != 0) return result;
        result = Nullable.Compare(theirs.LastUsed, mine.LastUsed);
        if (result != 0) return result;
        return string.Compare(mine.Title.Length > 0 ? mine.Title : left.Row.Title, theirs.Title.Length > 0 ? theirs.Title : right.Row.Title,
            StringComparison.OrdinalIgnoreCase);
    }

    #endregion
}
