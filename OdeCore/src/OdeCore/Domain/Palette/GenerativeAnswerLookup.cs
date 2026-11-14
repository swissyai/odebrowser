using System.Text.RegularExpressions;

using OdeCore.Contracts;

namespace OdeCore.Domain;

/// Privacy-safe typed-text eligibility for one local interpretation, not an action parser.
/// General text answers remain limited to the existing explicit/question/rewrite route.
public static partial class GenerativeAnswerLookup {
    #region Static Variables

    public const int MaximumInputLength = 512;
    public const int MaximumOutputLength = 1_200;
    private const string ExplicitPrefix = "ask ode ";

    #endregion

    #region Actions - Parsing

    /// The exact typed prompt, with only the explicit Ask Ode prefix removed.
    public static string Input(string text) {
        string trimmed = text.Trim();
        return trimmed.StartsWith(ExplicitPrefix, StringComparison.OrdinalIgnoreCase) ? trimmed[ExplicitPrefix.Length..].Trim() : trimmed;
    }

    public static PaletteGenerativeLookup? Of(string text) {
        string prompt = Input(text);
        if (prompt.Length is < 2 or > MaximumInputLength || prompt.Any(char.IsControl) || SecretText.Looks(prompt)
            || Sensitive().IsMatch(prompt) || HasAddress(prompt) || IsPrefix(text)
            || RewriteOpening().IsMatch(prompt) && !Rewrite().IsMatch(prompt)) return null;
        return new(prompt, IsExplicit(text));
    }

    /// Even an incomplete or sensitive explicit request must not be learned.
    public static bool IsExplicit(string text) => text.Trim().Equals(ExplicitPrefix.TrimEnd(), StringComparison.OrdinalIgnoreCase)
        || text.TrimStart().StartsWith(ExplicitPrefix, StringComparison.OrdinalIgnoreCase);

    public static bool IsRequest(string text) => IsExplicit(text) || Question().IsMatch(Input(text)) || Rewrite().IsMatch(Input(text));

    public static bool KeepsPrivate(string text, PalettePreferences preferences) =>
        IsExplicit(text) || preferences.Offers(PaletteSource.AskOde) && !string.IsNullOrWhiteSpace(text) && (IsPrefix(text)
            || IsRequest(text) || RewriteOpening().IsMatch(Input(text)) || Sensitive().IsMatch(text)
            || SecretText.Looks(text) || !HasAddress(Input(text)));

    private static bool IsPrefix(string text) => text.Trim().Length >= 3
        && ExplicitPrefix.StartsWith(text.Trim(), StringComparison.OrdinalIgnoreCase);

    private static bool HasAddress(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
        .Any(word => SecretText.Looks(word) || word.Contains('@', StringComparison.Ordinal) || word.Contains('/', StringComparison.Ordinal)
            || word.Contains('\\', StringComparison.Ordinal) || word.StartsWith('$') || word.Contains('=', StringComparison.Ordinal)
            || Host().IsMatch(word) && PaletteInterpretation.ReadNumber(word.TrimEnd('?', ';', '!')) is null || Scheme().IsMatch(word));

    /// Service status text can never become a copyable answer, nor can a
    /// result for a different prompt. Oversized output is rejected, not cut.
    public static PaletteCard? Card(PaletteGenerativeLookup lookup, PaletteGenerativeResult? result,
        PalettePreferences preferences, string source) {
        if (result?.Lookup != lookup) result = null;
        var status = result?.Status ?? PaletteGenerativeStatus.Waiting;
        if (status == PaletteGenerativeStatus.Answered && result?.Interpretation is { } interpretation)
            return interpretation.Resolve(lookup, preferences);
        if (!AllowsText(source, lookup.Text)) return null;
        string? text = result?.Text?.Trim();
        status = TextStatus(status, text);
        string? value = status == PaletteGenerativeStatus.Answered ? text : null;
        return new(PaletteCardKind.GenerativeAnswer, "Ode", "Private · On device", value ?? status.Message, value,
            Address: null, Term: null, Clock: null, Image: null, Credit: null, CreditAddress: null, License: null, LicenseAddress: null);
    }

    private static bool AllowsText(string source, string text) => Rewrite().IsMatch(Input(source))
        || IsRequest(source) && !NumericalRequest(text);

    private static PaletteGenerativeStatus TextStatus(PaletteGenerativeStatus status, string? text) =>
        status == PaletteGenerativeStatus.Answered && (string.IsNullOrWhiteSpace(text) || text.Length > MaximumOutputLength)
            ? PaletteGenerativeStatus.Failed : status;

    /// Text generation is never a fallback for a numerical request.
    public static bool NumericalRequest(string text) => ContainsNumber(text) || UnitConversion.MentionsUnit(text)
        || NumericIntent().IsMatch(text);

    internal static bool ContainsNumber(string text) => PaletteInterpretation.HasNumber(text);

    [GeneratedRegex(@"\b(?:calculate|calculation|convert|conversion|multiply|divide|subtract|percent|product|sum|plus|minus|times|squared|cubed)\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex NumericIntent();

    [GeneratedRegex(@"^(?:who|what|when|where|why|how)\s+(?:is|are|was|were|do|does|did|can|could|would|should|will|to)\s+\S+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Question();

    // Privacy starts at the recognized verb, before enough safe text exists to generate.
    [GeneratedRegex(@"^(?:rewrite|rephrase|proofread|summarize|shorten)(?:\s|:|$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex RewriteOpening();

    [GeneratedRegex(@"^(?:rewrite|rephrase|proofread|summarize|shorten)(?:\s*:\s*|\s+).{8,}$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Rewrite();

    [GeneratedRegex(@"\b(?:password|passphrase|credential|secret|token|api[ -]?key|private[ -]?key|recovery[ -]?(?:key|phrase)|seed[ -]?phrase)\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Sensitive();

    [GeneratedRegex(@"^[a-z][a-z0-9+.-]*:.+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Scheme();

    [GeneratedRegex(@"[\p{L}\p{N}-]+\.[\p{L}\p{N}-]{2,}", RegexOptions.CultureInvariant)]
    private static partial Regex Host();

    #endregion
}
