using System.Text.RegularExpressions;

namespace OdeCore.Domain;

/// Typed text that looks like something a person would not want a search
/// service to read: an email address, a key or token, a password, or a long
/// run of digits such as a card number. The palette sends none of it while a
/// person types. The rules lean towards holding text back, since a missed
/// suggestion costs little and a sent secret cannot be taken back.
internal static partial class SecretText {
    #region Static Variables

    /// The shortest run of letters and digits read as a key or token.
    private const int TokenLength = 24;

    /// The shortest run of letters in both cases, without digits, read as an
    /// encoded secret.
    private const int EncodedLength = 32;

    /// The shortest word read as a password.
    private const int PasswordLength = 8;

    /// The fewest digits read as a card or account number.
    private const int NumberDigits = 12;

    /// The shortest word a known key prefix starts that is read as a key.
    private const int PrefixedLength = 16;

    /// How common keys and tokens start.
    private static readonly string[] KeyPrefixes = [
        "sk-", "sk_", "pk_", "rk_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_", "glpat-", "xoxa-", "xoxb-", "xoxp-",
        "xoxr-", "akia", "asia", "aiza", "ya29.", "eyj",
    ];

    /// Marks that join ordinary words, such as in c++, node.js or AT&T, and
    /// so never make a word a password.
    private const string WordMarks = ".-_/+#&:'";

    #endregion

    #region Actions - Reading

    /// Whether `text` looks like a secret.
    public static bool Looks(string text) {
        ArgumentNullException.ThrowIfNull(text);
        string trimmed = text.Trim();
        if (trimmed.Length == 0) return false;
        if (Email().IsMatch(trimmed) || IsLongNumber(trimmed)) return true;
        string[] words = trimmed.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return words.Any(IsToken) || words.Length == 1 && IsPassword(trimmed);
    }

    /// A word that looks like a key or token: a long run that mixes letters
    /// and digits, a long run of digits, a longer run of letters in both
    /// cases, or a word that starts the way common keys do.
    private static bool IsToken(string word) {
        bool letters = word.Any(char.IsAsciiLetter), digits = word.Any(char.IsAsciiDigit);
        if (word.Length >= TokenLength && letters && digits) return true;
        if (word.Length >= NumberDigits && word.All(char.IsAsciiDigit)) return true;
        if (word.Length >= EncodedLength && word.Any(char.IsAsciiLetterUpper) && word.Any(char.IsAsciiLetterLower)) return true;
        return word.Length >= PrefixedLength
            && KeyPrefixes.Any(prefix => word.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
    }

    /// One word with letters, digits and a mark that ordinary words do not
    /// use, as passwords are made.
    private static bool IsPassword(string word) =>
        word.Length >= PasswordLength && word.Any(char.IsLetter) && word.Any(char.IsDigit)
        && word.Any(character => !char.IsLetterOrDigit(character) && !WordMarks.Contains(character));

    /// Text that is only a long number, written with or without spaces and
    /// dashes, as a card or account number is.
    private static bool IsLongNumber(string text) =>
        text.All(character => char.IsAsciiDigit(character) || character is ' ' or '-')
        && text.Count(char.IsAsciiDigit) >= NumberDigits;

    [GeneratedRegex(@"[^\s@]+@[^\s@]+\.[^\s@]{2,}", RegexOptions.CultureInvariant)]
    private static partial Regex Email();

    #endregion
}
