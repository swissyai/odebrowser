using System.Text;

namespace OdeCore.Domain;

/// Text folded into the words answers rank by: lowercased, without accents
/// or apostrophes, split at anything but letters, digits and the palette's
/// `@`, `$` and `%`, each word cut to a rough stem so "tabs" and "tab" or
/// "pinned" and "pin" meet. `Terms` leaves out the small words that every
/// question holds, unless the text is only such words; `Words` keeps them, so
/// a whole phrase can be compared. Text asks outright when it starts with a
/// question word or ends with a question mark, and reads as a question when
/// it asks outright or runs to three or more words with one of the small
/// words among them.
internal sealed class AnswerText {
    #region Static Variables

    private static readonly HashSet<string> StopWords = new(StringComparer.Ordinal) {
        "a", "an", "the", "i", "im", "me", "my", "we", "our", "you", "your", "it", "its", "to", "of", "in", "on", "at", "for",
        "with", "and", "or", "but", "is", "are", "was", "be", "been", "do", "doe", "does", "did", "how", "can", "could",
        "would", "should", "will", "what", "where", "why", "when", "which", "who", "there", "here", "this", "that", "these",
        "those", "please", "help", "want", "wanna", "need", "get", "got", "make", "way", "ode", "browser", "just", "any",
        "some", "one", "into", "from", "by", "about", "as", "so", "if", "not", "no", "up", "dont", "doesnt", "cant", "isnt",
        "wont", "didnt"
    };

    private static readonly HashSet<string> QuestionWords = new(StringComparer.Ordinal) {
        "how", "where", "what", "why", "when", "which", "who", "can", "could", "does", "do", "is", "are", "should", "will",
        "would", "whats", "wheres", "hows", "whys"
    };

    /// Endings cut from a word, longest first, and what replaces each, so
    /// long as at least three letters stay.
    private static readonly (string Ending, string Replacement)[] Endings =
        [("sses", "ss"), ("ies", "y"), ("ing", ""), ("ed", ""), ("es", ""), ("s", "")];

    private const int ShortestStem = 3;

    #endregion

    #region Variables

    /// The stems that rank, without the small words unless they are all
    /// there is.
    public IReadOnlyList<string> Terms { get; }

    /// Every stem, small words included, in order.
    public IReadOnlyList<string> Words { get; }

    /// Every stem joined by single spaces, for comparing whole phrases.
    public string Phrase { get; }

    public bool ReadsAsQuestion { get; }

    public bool AsksOutright { get; }

    /// Whether the text holds a word beyond the small ones, as "what is the"
    /// does not.
    public bool HasContent { get; }

    /// Whether the text may name a title in its own words: it asks nothing
    /// outright and holds two words or more beyond the small ones.
    public bool NamesInWords => !AsksOutright && HasContent && Terms.Count >= 2;

    #endregion

    #region Constructors

    private AnswerText(IReadOnlyList<string> raw, bool endsWithQuestionMark) {
        Words = [.. raw.Select(Stem)];
        var meaningful = raw.Where(word => !StopWords.Contains(word)).Select(Stem).ToList();
        HasContent = meaningful.Count > 0;
        Terms = HasContent ? meaningful : Words;
        Phrase = string.Join(' ', Words);
        AsksOutright = raw.Count > 0 && (endsWithQuestionMark || QuestionWords.Contains(raw[0]));
        ReadsAsQuestion = AsksOutright || raw.Count >= 3 && raw.Any(StopWords.Contains);
    }

    #endregion

    #region Actions - Reading

    /// `text` folded into stems.
    public static AnswerText Of(string text) {
        ArgumentNullException.ThrowIfNull(text);
        string trimmed = text.Trim();
        return new([.. Split(Folded(trimmed))], trimmed.EndsWith('?'));
    }

    /// How many of `title`'s words, small ones aside, the text leaves out
    /// when it names the title in its own words: when its words are the
    /// title's, or when, asking nothing outright, it holds two words or more
    /// beyond the small ones and each is a word of the title, as "close this
    /// window" names Close Window and "pin tab" Pin or Unpin Current Tab.
    /// Null when it does not name the title.
    public int? Leaves(string title) {
        var named = Of(title);
        if (Phrase == named.Phrase) return 0;
        if (!NamesInWords || !Terms.All(named.Words.Contains)) return null;
        return named.Terms.Count(term => !Terms.Contains(term));
    }

    /// `word`, already folded, cut to its stem: one ending off, a doubled
    /// last letter made single and a final silent e dropped, so "pinned",
    /// "pinning" and "pin", or "archived" and "archive", meet.
    public static string Stem(string word) {
        string stem = word;
        foreach (var (ending, replacement) in Endings)
            if (stem.EndsWith(ending, StringComparison.Ordinal) && stem.Length - ending.Length >= ShortestStem) {
                stem = string.Concat(stem.AsSpan(0, stem.Length - ending.Length), replacement);
                break;
            }
        if (stem.Length > ShortestStem && stem[^1] == stem[^2] && char.IsLetter(stem[^1]) && stem[^1] is not ('l' or 's' or 'z'))
            stem = stem[..^1];
        if (stem.Length > ShortestStem && stem[^1] == 'e') stem = stem[..^1];
        return stem;
    }

    /// `text` folded as the core folds text, without apostrophes or curly
    /// quotes.
    private static string Folded(string text) {
        string folded = TextFold.Folded(text);
        var builder = new StringBuilder(folded.Length);
        foreach (char character in folded)
            if (character is not ('\'' or '’' or '‘')) builder.Append(character);
        return builder.ToString();
    }

    /// The words of folded `text`: runs of letters, digits, `@`, `$` and `%`.
    private static IEnumerable<string> Split(string text) {
        var word = new StringBuilder();
        foreach (char character in text) {
            if (char.IsLetterOrDigit(character) || character is '@' or '$' or '%') {
                word.Append(character);
                continue;
            }
            if (word.Length > 0) yield return word.ToString();
            word.Clear();
        }
        if (word.Length > 0) yield return word.ToString();
    }

    #endregion
}
