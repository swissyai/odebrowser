namespace OdeCore.Contracts;

/// The runs of a row's title the platform sets in bold for what was typed,
/// in order and apart: for a search suggestion, what it adds to the typed
/// text, or each of its words the typed text lacks when it does not start
/// with it; for a tab, folder or page, every place a typed word appears in
/// it, matched as the palette matches words. A row with an emphasis and no
/// runs still shows its title in the weight emphasized titles share.
public sealed record PaletteEmphasis(IReadOnlyList<TextRun> Runs) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<TextRun> Runs {
        get;
        init => field = [.. value];
    } = [.. Runs];

    #endregion

    #region Actions - Equality

    public bool Equals(PaletteEmphasis? other) => other is not null && Runs.SequenceEqual(other.Runs);

    public override int GetHashCode() => Runs.Count;

    #endregion
}

/// A stretch of a text the platform shows: the UTF-16 offset it starts at
/// and how many UTF-16 units it holds.
public sealed record TextRun(int Start, int Length);
