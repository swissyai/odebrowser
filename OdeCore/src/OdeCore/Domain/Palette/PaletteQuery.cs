using System.Collections.Concurrent;
using System.Globalization;
using System.Text;

using OdeCore.Contracts;

namespace OdeCore.Domain;

#region Types

/// How well typed text matched a page: its points, where in the address the
/// earliest term landed, or `int.MaxValue` for a title-only match, and
/// whether a term starts one of the host's labels.
public readonly record struct PlaceMatch(int Points, int Offset, bool StartsHostLabel);

#endregion

/// What a person typed into the palette, trimmed and folded once into its
/// whitespace-separated terms, so every candidate is matched against the same
/// folded text. Matching uses canonical Unicode equivalence and ignores case
/// and accents: each letter is compared by its base letters, so "cafe" finds
/// "Café", "resume" finds "Résumé", "strasse" finds "Straße" and "istanbul"
/// finds "İstanbul"; a final sigma is a sigma. Compatibility forms such as
/// ligatures and full-width letters stay distinct.
public sealed class PaletteQuery {
    #region Static Variables

    /// What a term matched in a row's detail scores less than the same match
    /// in its title.
    private const int DetailPenalty = 150;
    /// A word typed as the initials of a title's words.
    private const int InitialsPoints = 250;
    /// A word whose letters appear in a title in order.
    private const int SubsequencePoints = 150;
    /// A term shorter than this matches nothing inside a title word.
    private const int ShortestInsideTerm = 3;
    /// A page whose title is exactly the text, or whose host or host name is.
    private const int ExactBonus = 300;
    /// A page one of whose host labels is exactly the text.
    private const int HostLabelBonus = 100;
    private static readonly Rune FinalSigma = new('ς');
    private static readonly Rune Sigma = new('σ');
    /// The most base letters one character folds to (a Hangul syllable's jamo).
    private const int MaxFold = 8;
    /// How each non-ASCII character folds, worked out once per character.
    private static readonly ConcurrentDictionary<int, Rune[]> NonAsciiFolds = new();

    #endregion

    #region Variables

    /// The text as typed, trimmed.
    public string Text { get; }

    /// Nothing but whitespace was typed.
    public bool IsEmpty => terms.Length == 0;

    private readonly Rune[][] terms;

    /// The terms folded and joined by one space, for exact comparisons.
    private readonly string folded;

    #endregion

    #region Constructors

    public PaletteQuery(string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        Text = typed.Trim();
        List<Rune[]> found = [];
        List<Rune> current = [];
        Span<Rune> letters = stackalloc Rune[MaxFold];
        foreach (var rune in TextFold.Normalized(Text).EnumerateRunes()) {
            if (IsWhitespace(rune)) {
                if (current.Count > 0) found.Add([.. current]);
                current.Clear();
                continue;
            }
            int count = Fold(rune, letters);
            for (int index = 0; index < count; index++) current.Add(letters[index]);
        }
        if (current.Count > 0) found.Add([.. current]);
        terms = [.. found];
        folded = string.Join(' ', terms.Select(term => string.Concat(term.Select(rune => rune.ToString()))));
    }

    #endregion

    #region Actions - Scoring

    /// How well every term matches `title`, or else `detail` for less, as the
    /// average points of each term's best match; null when a term matches
    /// neither or nothing was typed.
    public int? Score(string title, string detail = "") {
        ArgumentNullException.ThrowIfNull(title);
        ArgumentNullException.ThrowIfNull(detail);
        if (IsEmpty) return null;
        title = TextFold.Normalized(title);
        detail = TextFold.Normalized(detail);
        int total = 0;
        foreach (var term in terms) {
            if (Match(term, title) is { } inTitle) {
                total += inTitle.Match.Points;
                continue;
            }
            if (detail.Length > 0 && Match(term, detail) is { } inDetail) {
                total += Math.Max(0, inDetail.Match.Points - DetailPenalty);
                continue;
            }
            return null;
        }
        return total / terms.Length;
    }

    /// How well every term matches the page `place`: each term's best class
    /// in the title, a host label, a path segment or the query string,
    /// averaged over the terms, plus one bonus for the row: its core title is
    /// exactly the text, its host or host name is, or one of its host labels
    /// is. Null when a term matches nowhere or nothing was typed.
    public PlaceMatch? Score(PlaceText place) {
        ArgumentNullException.ThrowIfNull(place);
        if (IsEmpty) return null;
        int total = 0;
        int offset = int.MaxValue;
        bool startsLabel = false;
        foreach (var term in terms) {
            TextMatch? best = null;
            if (Match(term, place.Title) is { } inTitle && (inTitle.Match != TextMatch.Inside || term.Length >= ShortestInsideTerm))
                best = inTitle.Match;
            for (int index = 0; index < place.HostLabels.Count; index++) {
                if (Match(term, place.HostLabels[index]) is not { } inLabel) continue;
                var match = inLabel.Match == TextMatch.TextStart ? TextMatch.HostLabelStart : TextMatch.HostInside;
                startsLabel |= match == TextMatch.HostLabelStart;
                best = Best(best, match);
                offset = Math.Min(offset, place.HostLabelOffsets[index] + inLabel.Offset);
            }
            for (int index = 0; index < place.PathSegments.Count; index++) {
                if (Match(term, place.PathSegments[index]) is not { } inSegment) continue;
                best = Best(best, inSegment.Match == TextMatch.Inside ? TextMatch.AddressInside : TextMatch.PathStart);
                offset = Math.Min(offset, place.PathSegmentOffsets[index] + inSegment.Offset);
            }
            if (place.Query.Length > 0 && Match(term, place.Query) is { } inQuery) {
                best = Best(best, TextMatch.AddressInside);
                offset = Math.Min(offset, place.QueryOffset + inQuery.Offset);
            }
            if (best is null) return null;
            total += best.Points;
        }
        return new(total / terms.Length + Bonus(place), offset, startsLabel);
    }

    /// Whether what was typed, as one text, starts `text`, ignoring case:
    /// "amazon" starts "amazon.de/" and "emblem br" starts "Ode Browser".
    public bool Prefixes(string text) {
        ArgumentNullException.ThrowIfNull(text);
        return PrefixesNormalized(TextFold.Normalized(text));
    }

    /// `Prefixes` for a text already canonically normalized, such as one a
    /// `PlaceText` holds, which reads only as far as the first difference.
    internal bool PrefixesNormalized(string text) {
        if (IsEmpty) return false;
        int term = 0;
        int position = 0;
        bool needsGap = false;
        bool inGap = false;
        Span<Rune> letters = stackalloc Rune[MaxFold];
        foreach (var rune in text.EnumerateRunes()) {
            bool space = IsWhitespace(rune);
            int count = space ? 0 : Fold(rune, letters);
            if (!space && count == 0) continue;
            if (needsGap) {
                if (!space) return false;
                needsGap = false;
                inGap = true;
                continue;
            }
            if (inGap && space) continue;
            inGap = false;
            if (space) return false;
            for (int index = 0; index < count; index++) {
                if (needsGap) return false;
                if (letters[index] != terms[term][position]) return false;
                if (++position < terms[term].Length) continue;
                if (++term == terms.Length) return true;
                position = 0;
                needsGap = true;
            }
        }
        return false;
    }

    /// How well one typed word abbreviates `title` as the initials of its
    /// words ("tsv" for Toggle Split View); null when it does not, or for more
    /// than one word or a single letter.
    public int? Initials(string title) {
        ArgumentNullException.ThrowIfNull(title);
        if (terms.Length != 1 || terms[0].Length < 2) return null;
        var term = terms[0];
        List<Rune> initials = [];
        Rune? previous = null;
        Span<Rune> letters = stackalloc Rune[MaxFold];
        foreach (var rune in TextFold.Normalized(title).EnumerateRunes()) {
            int count = Fold(rune, letters);
            if (count == 0) continue;
            if (!IsBoundary(rune) && (previous is not { } before || IsBoundary(before))) initials.Add(letters[0]);
            previous = rune;
        }
        return initials.Count >= term.Length && term.Select((rune, index) => initials[index] == rune).All(matches => matches)
            ? InitialsPoints : null;
    }

    /// How well one typed word abbreviates `title`: as the initials of its
    /// words, or as letters it holds in order; null for neither, or for more
    /// than one word or a single letter.
    public int? Abbreviates(string title) {
        if (Initials(title) is { } initials) return initials;
        if (terms.Length != 1 || terms[0].Length < 2) return null;
        var term = terms[0];
        int found = 0;
        Span<Rune> letters = stackalloc Rune[MaxFold];
        foreach (var rune in TextFold.Normalized(title).EnumerateRunes()) {
            int count = Fold(rune, letters);
            for (int index = 0; index < count && found < term.Length; index++)
                if (letters[index] == term[found]) found++;
        }
        return found == term.Length ? SubsequencePoints : null;
    }

    /// The bonus the whole text earns on `place`: its core title is exactly
    /// the text, its host or host name is, or failing that one of its host
    /// labels is.
    private int Bonus(PlaceText place) {
        if (place.FoldedCore == folded) return ExactBonus;
        if (terms.Length != 1) return 0;
        if (place.Host == folded || place.Name == folded) return ExactBonus;
        return place.HostLabels.Contains(folded, StringComparer.Ordinal) ? HostLabelBonus : 0;
    }

    /// The best place `term` appears in `text`: where it starts the text, where
    /// it starts a word, or anywhere else; null when it does not appear.
    private static Hit? Match(Rune[] term, string text) {
        Hit? best = null;
        Rune? previous = null;
        var runes = text.EnumerateRunes();
        int index = 0;
        Span<Rune> letters = stackalloc Rune[MaxFold];
        foreach (var rune in runes) {
            int count = Fold(rune, letters);
            if (count == 0) {
                index += rune.Utf16SequenceLength;
                continue;
            }
            if (letters[0] == term[0] && MatchedLength(term, text, index) >= 0) {
                var match = previous is not { } before ? TextMatch.TextStart
                    : IsBoundary(before) ? TextMatch.WordStart : TextMatch.Inside;
                if (match == TextMatch.TextStart) return new(match, index);
                if (best is not { } known || match.Points > known.Match.Points) best = new(match, index);
                if (match == TextMatch.WordStart) return best;
            }
            previous = rune;
            index += rune.Utf16SequenceLength;
        }
        return best;
    }

    /// How many UTF-16 units of `text` from the offset `start` `term`
    /// matches, or -1 when it does not appear there. A term may end inside a
    /// letter that folds to several ("stras" in "Straße"), and the accents
    /// that follow its last letter belong to the match.
    private static int MatchedLength(Rune[] term, string text, int start) {
        int position = start;
        int matched = 0;
        Span<Rune> letters = stackalloc Rune[MaxFold];
        while (matched < term.Length) {
            if (!TryRead(text, position, out var rune, out int length)) return -1;
            int count = Fold(rune, letters);
            if (count == 0) {
                if (position == start) return -1;
                position += length;
                continue;
            }
            for (int index = 0; index < count && matched < term.Length; index++) {
                if (letters[index] != term[matched]) return -1;
                matched++;
            }
            position += length;
        }
        while (TryRead(text, position, out var mark, out int length) && Fold(mark, letters) == 0) position += length;
        return position - start;
    }

    private static bool TryRead(string text, int position, out Rune rune, out int length) {
        if (position < text.Length
            && Rune.DecodeFromUtf16(text.AsSpan(position), out rune, out length) == System.Buffers.OperationStatus.Done)
            return true;
        rune = default;
        length = 0;
        return false;
    }

    /// Every place a term appears in `text`, already normalized, each found
    /// from the end of the one before, as UTF-16 runs of `text`, term by
    /// term in the order they were typed.
    internal IEnumerable<TextRun> Occurrences(string text) {
        ArgumentNullException.ThrowIfNull(text);
        foreach (var term in terms) {
            int index = 0;
            while (index < text.Length) {
                int length = MatchedLength(term, text, index);
                if (length > 0) {
                    yield return new(index, length);
                    index += length;
                } else {
                    index += char.IsSurrogatePair(text, index) ? 2 : 1;
                }
            }
        }
    }

    private static TextMatch Best(TextMatch? known, TextMatch found) => known is null ? found : known.Better(found);

    #endregion

    #region Actions - Folding

    /// `text`, already normalized, folded as the terms are and with its
    /// whitespace collapsed to single spaces, for exact comparisons.
    internal static string FoldedText(string text) {
        var builder = new StringBuilder(text.Length);
        bool space = false;
        Span<Rune> letters = stackalloc Rune[MaxFold];
        foreach (var rune in text.EnumerateRunes()) {
            if (IsWhitespace(rune)) {
                space = builder.Length > 0;
                continue;
            }
            if (space) builder.Append(' ');
            space = false;
            int count = Fold(rune, letters);
            for (int index = 0; index < count; index++) builder.Append(letters[index].ToString());
        }
        return builder.ToString();
    }

    /// The base letters `rune` is compared by, lowercased, written into
    /// `letters`; how many there are. Accents and other nonspacing marks fold
    /// to nothing, ß and ẞ to "ss", a final sigma to a sigma.
    private static int Fold(Rune rune, Span<Rune> letters) {
        if (rune.IsAscii) {
            letters[0] = rune.Value is >= 'A' and <= 'Z' ? new Rune(rune.Value + 32) : rune;
            return 1;
        }
        var folded = NonAsciiFolds.GetOrAdd(rune.Value, static value => FoldNonAscii(new Rune(value)));
        folded.CopyTo(letters);
        return folded.Length;
    }

    private static Rune[] FoldNonAscii(Rune rune) {
        if (rune == FinalSigma) return [Sigma];
        if (rune.Value is 0x00DF or 0x1E9E) return [new('s'), new('s')];
        if (Rune.GetUnicodeCategory(rune) == UnicodeCategory.NonSpacingMark) return [];
        List<Rune> letters = [];
        foreach (var part in rune.ToString().Normalize(NormalizationForm.FormD).EnumerateRunes())
            if (Rune.GetUnicodeCategory(part) != UnicodeCategory.NonSpacingMark) letters.Add(Rune.ToLowerInvariant(part));
        return letters.Count <= MaxFold ? [.. letters] : [.. letters.Take(MaxFold)];
    }

    private static bool IsWhitespace(Rune rune) => rune.IsAscii ? rune.Value is ' ' or '\t' : Rune.IsWhiteSpace(rune);

    /// A character that ends a word: anything but a letter or a number.
    private static bool IsBoundary(Rune rune) {
        if (rune.IsAscii) return !(rune.Value is >= '0' and <= '9' or >= 'A' and <= 'Z' or >= 'a' and <= 'z');
        return !(Rune.IsLetter(rune) || Rune.IsNumber(rune));
    }

    #endregion

    #region Types

    /// Where one term matched a text: how, and at which UTF-16 offset.
    private readonly record struct Hit(TextMatch Match, int Offset);

    #endregion
}
