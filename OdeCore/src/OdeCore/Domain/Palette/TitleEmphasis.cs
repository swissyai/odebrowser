using System.Globalization;
using System.Text;

using OdeCore.Contracts;

namespace OdeCore.Domain;

/// Which parts of a row's title the palette marks for what was typed, as the
/// row's kind asks. A search suggestion, which the palette compares with the
/// typed text without case or diacritics, marks what follows the typed text
/// when it starts with it, or else each of its words the typed text lacks. A
/// tab, folder or page, which the palette found by its words, marks every
/// place a typed word appears in its title, matched as the palette matches
/// words, so the marks never claim a match the palette did not make. Runs
/// count UTF-16 units of the title as the row holds it, whole characters
/// only, in order and apart.
internal sealed class TitleEmphasis {
    #region Static Variables

    /// What a search suggestion adds to the typed text.
    public static readonly TitleEmphasis Completion = new(Completed);

    /// Every place a typed word appears.
    public static readonly TitleEmphasis Matches = new(Matched);

    #endregion

    #region Variables

    private readonly Func<PaletteQuery, string, List<TextRun>> runs;

    #endregion

    #region Constructors

    private TitleEmphasis(Func<PaletteQuery, string, List<TextRun>> runs) => this.runs = runs;

    #endregion

    #region Actions - Marking

    /// What of `row`'s title `query` marks, or null when nothing was typed or
    /// the row's kind keeps its title one weight.
    public static PaletteEmphasis? Of(PaletteRow row, PaletteQuery query) {
        ArgumentNullException.ThrowIfNull(row);
        ArgumentNullException.ThrowIfNull(query);
        return row.Kind.Emphasis is { } emphasis && !query.IsEmpty ? new(emphasis.runs(query, row.Title)) : null;
    }

    /// What follows the typed text in `title` when, folded, the title starts
    /// with it, ending on a whole character; otherwise each word of the title
    /// that, folded, is none of the typed words.
    private static List<TextRun> Completed(PaletteQuery query, string title) {
        if (CompletedFrom(TextFold.Folded(query.Text), title) is { } end)
            return end < title.Length ? [new(end, title.Length - end)] : [];
        var typed = query.Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Select(TextFold.Folded)
            .ToHashSet(StringComparer.Ordinal);
        return [.. Words(title).Where(word => !typed.Contains(TextFold.Folded(title.Substring(word.Start, word.Length))))];
    }

    /// The UTF-16 offset in `title` where its folded characters spell
    /// `folded` from its start, or null when they do not.
    private static int? CompletedFrom(string folded, string title) {
        int spelled = 0;
        var elements = StringInfo.GetTextElementEnumerator(title);
        while (spelled < folded.Length && elements.MoveNext()) {
            string element = TextFold.Folded(elements.GetTextElement());
            if (spelled + element.Length > folded.Length
                || string.CompareOrdinal(folded, spelled, element, 0, element.Length) != 0) return null;
            spelled += element.Length;
            if (spelled == folded.Length) return elements.ElementIndex + elements.GetTextElement().Length;
        }
        return null;
    }

    /// Every place a typed word appears in `title`, matched as the palette
    /// matches words, merged where runs touch.
    private static List<TextRun> Matched(PaletteQuery query, string title) {
        string normalized = TextFold.Normalized(title);
        if (string.Equals(normalized, title, StringComparison.Ordinal)) return Merged(query.Occurrences(title));
        return InTitle(title, normalized) is { } map ? Merged(query.Occurrences(normalized).Select(map)) : [];
    }

    /// How a run of `normalized`, the normalized `title`, covers `title`:
    /// from the start of the character it starts in to the end of the one it
    /// ends in. Null when normalizing each character apart does not give
    /// `normalized`, so no run can be placed.
    private static Func<TextRun, TextRun>? InTitle(string title, string normalized) {
        List<int> starts = [];
        List<int> originals = [];
        var joined = new StringBuilder(normalized.Length);
        var elements = StringInfo.GetTextElementEnumerator(title);
        while (elements.MoveNext()) {
            starts.Add(joined.Length);
            originals.Add(elements.ElementIndex);
            joined.Append(TextFold.Normalized(elements.GetTextElement()));
        }
        if (!string.Equals(joined.ToString(), normalized, StringComparison.Ordinal)) return null;
        originals.Add(title.Length);
        int Containing(int offset) {
            int found = starts.BinarySearch(offset);
            return found >= 0 ? found : ~found - 1;
        }
        return run => {
            int first = Containing(run.Start);
            int last = Containing(run.Start + run.Length - 1);
            return new(originals[first], originals[last + 1] - originals[first]);
        };
    }

    /// The words of `title`: runs of letters, digits, marks and connectors,
    /// kept whole across an apostrophe or full stop between two of them, as
    /// "don't" and "e.g", and across a comma between two digits, as "1,000".
    private static IEnumerable<TextRun> Words(string title) {
        int? start = null;
        var previous = Rune.ReplacementChar;
        int index = 0;
        while (index < title.Length) {
            var rune = RuneAt(title, index, out int length);
            int next = index + length;
            if (IsWordPart(rune) || start is not null && next < title.Length && Joins(previous, rune, RuneAt(title, next, out _))) {
                start ??= index;
            } else if (start is { } begun) {
                yield return new(begun, index - begun);
                start = null;
            }
            previous = rune;
            index = next;
        }
        if (start is { } last) yield return new(last, title.Length - last);
    }

    /// Whether `rune`, between `before` and `after`, keeps one word whole.
    private static bool Joins(Rune before, Rune rune, Rune after) => rune.Value switch {
        '\'' or '’' or '.' => IsWordPart(before) && IsWordPart(after),
        ',' => Rune.IsDigit(before) && Rune.IsDigit(after),
        _ => false,
    };

    private static bool IsWordPart(Rune rune) => Rune.IsLetterOrDigit(rune) || Rune.GetUnicodeCategory(rune)
        is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark
        or UnicodeCategory.ConnectorPunctuation;

    /// The character at the UTF-16 offset `index` of `text`, U+FFFD for a
    /// lone surrogate, and how many UTF-16 units it takes.
    private static Rune RuneAt(string text, int index, out int length) {
        Rune.DecodeFromUtf16(text.AsSpan(index), out var rune, out length);
        return rune;
    }

    /// `runs` in order, those that overlap or touch joined into one.
    private static List<TextRun> Merged(IEnumerable<TextRun> runs) {
        List<TextRun> merged = [];
        foreach (var run in runs.OrderBy(run => run.Start)) {
            if (merged.Count > 0 && merged[^1] is var last && run.Start <= last.Start + last.Length) {
                int end = Math.Max(last.Start + last.Length, run.Start + run.Length);
                merged[^1] = last with { Length = end - last.Start };
            } else {
                merged.Add(run);
            }
        }
        return merged;
    }

    #endregion
}
