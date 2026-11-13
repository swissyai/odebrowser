using System.Text.RegularExpressions;

using OdeCore.Contracts;

namespace OdeCore.Domain;

/// Which word the palette asks the Mac's dictionary about, and the card it
/// makes of the answer. A person asks outright, as "define ephemeral",
/// "ephemeral meaning" or "what does ephemeral mean" do, or types one word,
/// which the dictionary may know. The platform looks the word up on the
/// device; nothing leaves it.
internal static partial class DictionaryLookup {
    #region Static Variables

    /// The longest word or phrase the palette looks up.
    private const int MaximumLength = 40;

    /// The fewest letters a single typed word needs to be looked up without
    /// being asked for.
    private const int MinimumWord = 3;

    /// The most of an entry a card shows.
    private const int MaximumBody = 280;

    #endregion

    #region Actions - Asking

    /// The word or phrase `text` asks the dictionary about, or null: what an
    /// outright question names, else the one word typed.
    public static string? Term(string text) {
        ArgumentNullException.ThrowIfNull(text);
        string trimmed = text.Trim().TrimEnd('?').Trim();
        if (trimmed.Length is 0 or > MaximumLength + 24) return null;
        if (Asking().Match(trimmed.ToLowerInvariant()) is { Success: true } asked) {
            string term = asked.Groups["term"].Value.Trim();
            return term.Length is > 0 and <= MaximumLength && IsWords(term) ? term : null;
        }
        return trimmed.Length is >= MinimumWord and <= MaximumLength && !trimmed.Contains(' ', StringComparison.Ordinal)
            && IsWords(trimmed) ? trimmed : null;
    }

    /// Whether `text` asks the dictionary outright, so a card says so even
    /// when the Mac has no dictionary yet.
    public static bool AsksOutright(string text) {
        ArgumentNullException.ThrowIfNull(text);
        return Asking().IsMatch(text.Trim().TrimEnd('?').Trim().ToLowerInvariant());
    }

    #endregion

    #region Actions - Answering

    /// The card for what the dictionary said for `definition.Term`, or null.
    /// An entry the Mac writes as headword, pronunciation and the rest, each
    /// after a bar, keeps that shape; any other shows whole, shortened. With
    /// no dictionary yet, an outright question gets a card that says so.
    public static PaletteCard? Card(PaletteDefinition definition, bool askedOutright) {
        ArgumentNullException.ThrowIfNull(definition);
        if (definition.Text is not { } text) {
            return askedOutright
                ? Card(definition.Term, "", "The Mac is still downloading its dictionary. Definitions show here once it's ready.")
                : null;
        }
        string[] parts = text.Split(" | ", 3, StringSplitOptions.TrimEntries);
        return parts.Length == 3 && parts[0].Length > 0
            ? Card(definition.Term, parts[1], Shortened(parts[2]), headword: Headword(parts[0], definition.Term))
            : Card(definition.Term, "", Shortened(text.Trim()));
    }

    private static PaletteCard Card(string term, string pronunciation, string body, string? headword = null) =>
        new(PaletteCardKind.Definition, headword ?? term, pronunciation, body, Value: null, Address: null, term, Clock: null,
            Image: null, Credit: "Dictionary", CreditAddress: null, License: null, LicenseAddress: null);

    /// The headword the entry leads with, without the plain word the Mac
    /// writes before its divided spelling, as "ephemeral e·phem·er·al" has.
    private static string Headword(string written, string term) {
        string[] words = written.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
        return words.Length == 2 && string.Equals(words[0], term, StringComparison.OrdinalIgnoreCase)
            && string.Equals(words[1].Replace("·", "", StringComparison.Ordinal), term, StringComparison.OrdinalIgnoreCase)
            ? words[1] : written;
    }

    /// `text` cut at a word near `MaximumBody` characters, with an ellipsis.
    private static string Shortened(string text) {
        string collapsed = string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (collapsed.Length <= MaximumBody) return collapsed;
        int cut = collapsed.LastIndexOf(' ', MaximumBody);
        return collapsed[..(cut > MaximumBody / 2 ? cut : MaximumBody)].TrimEnd(',', ';', ':', '.') + "…";
    }

    /// Letters, with the apostrophes, hyphens and spaces words carry.
    private static bool IsWords(string text) =>
        text.Any(char.IsLetter) && text.All(character => char.IsLetter(character) || character is '\'' or '’' or '-' or ' ');

    [GeneratedRegex(@"^(?:define\s+(?<term>.+)|definition\s+of\s+(?<term>.+)|meaning\s+of\s+(?<term>.+)|what\s+does\s+(?<term>.+?)\s+mean|what\s+is\s+the\s+meaning\s+of\s+(?<term>.+)|(?<term>.+?)\s+(?:meaning|definition|defined))$",
        RegexOptions.CultureInvariant)]
    private static partial Regex Asking();

    #endregion
}
