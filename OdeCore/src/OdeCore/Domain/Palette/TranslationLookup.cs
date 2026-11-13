using System.Globalization;
using System.Text.RegularExpressions;

using OdeCore.Contracts;

namespace OdeCore.Domain;

/// A small, deterministic grammar for an optional inline translation. Only
/// catalog language names count, never countries or URLs. Search still leads.
public static partial class TranslationLookup {
    #region Static Variables

    private const int MaximumLength = 512;
    private static readonly Lazy<IReadOnlyDictionary<string, string>> Languages = new(() =>
        CultureInfo.GetCultures(CultureTypes.NeutralCultures)
            .Where(culture => culture.Name.Length > 0 && LanguageTag.Parse(culture.Name) is not null)
            .SelectMany(culture => new[] { culture.EnglishName, culture.NativeName }.Select(name => (Name: name, Id: culture.Name)))
            .GroupBy(entry => entry.Name, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Id, StringComparer.OrdinalIgnoreCase));

    #endregion

    #region Actions - Parsing

    /// A recognizable request stays private even before a supported language
    /// or a safe phrase can be parsed. A translate website is still an address.
    public static bool IsExplicit(string text) => PrivateIntent().IsMatch(text.Trim());

    public static PaletteTranslationLookup? Of(string text) {
        text = text.Trim();
        if (text.Length is 0 or > MaximumLength || text.Any(char.IsControl) || SecretText.Looks(text)) return null;
        var (match, explicitIntent) = Match(text);
        if (!match.Success || !Languages.Value.TryGetValue(match.Groups["target"].Value.Trim().TrimEnd('?'), out string? target)) return null;
        if (Phrase(match.Groups["phrase"].Value.Trim(), explicitIntent) is not { } phrase) return null;
        return new(phrase.Text, phrase.Source, target);
    }

    private static (Match Match, bool Explicit) Match(string text) {
        var match = Explicit().Match(text);
        if (match.Success) return (match, true);
        match = Saying().Match(text);
        return match.Success ? (match, true) : (Implicit().Match(text), false);
    }

    private static (string Text, string? Source)? Phrase(string phrase, bool explicitIntent) {
        string? source = null;
        if (explicitIntent && Source().Match(phrase) is { Success: true } from) {
            if (!Languages.Value.TryGetValue(from.Groups["source"].Value.Trim(), out source)) return null;
            phrase = from.Groups["phrase"].Value.Trim();
        }
        bool quoted = phrase.Length > 1 && (phrase[0], phrase[^1]) is ('"', '"') or ('“', '”') or ('\'', '\'');
        if (quoted) phrase = phrase[1..^1].Trim();
        if (!phrase.Any(char.IsLetter) || HasAddress(phrase)) return null;
        return (phrase, source);
    }

    private static bool HasAddress(string phrase) => phrase.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
        .Any(word => word.TrimEnd('.', ',', '!', '?').Contains('.', StringComparison.Ordinal) || word.Contains('/', StringComparison.Ordinal)
            || word.Contains(':', StringComparison.Ordinal) || word.Contains('@', StringComparison.Ordinal));

    /// The platform's output is accepted only for the exact request. A
    /// status can never masquerade as copyable translated text.
    public static PaletteCard Card(PaletteTranslationLookup lookup, PaletteTranslationResult? result) {
        if (result?.Lookup != lookup) result = null;
        var status = result?.Status ?? PaletteTranslationStatus.Waiting;
        if (status == PaletteTranslationStatus.Translated && string.IsNullOrWhiteSpace(result?.Text)) status = PaletteTranslationStatus.Failed;
        string? value = status == PaletteTranslationStatus.Translated ? result?.Text : null;
        string target = Name(lookup.TargetLanguage);
        return new(PaletteCardKind.Translation, value ?? target, value is null ? "" : Direction(target, result?.SourceLanguage),
            value is null ? status.Message : lookup.Text, value,
            Address: null, Term: null, Clock: null, Image: null, Credit: null, CreditAddress: null, License: null, LicenseAddress: null);
    }

    private static string Direction(string target, string? source) => source is null ? target : $"{Name(source)} → {target}";

    private static string Name(string language) {
        try {
            return CultureInfo.GetCultureInfo(language).EnglishName;
        } catch (CultureNotFoundException) {
            return language;
        }
    }

    [GeneratedRegex(@"^(?:translate(?:\s|$)|how\s+do\s+you\s+say(?:\s|$))", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PrivateIntent();

    [GeneratedRegex(@"^translate\s+(?<phrase>.+)\s+(?:to|into)\s+(?<target>[\p{L}\p{M} ()-]+)\??$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Explicit();

    [GeneratedRegex(@"^how\s+do\s+you\s+say\s+(?<phrase>.+)\s+in\s+(?<target>[\p{L}\p{M} ()-]+)\??$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Saying();

    [GeneratedRegex(@"^(?<phrase>.+)\s+in\s+(?<target>[\p{L}\p{M} ()-]+)\??$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Implicit();

    [GeneratedRegex(@"^(?<phrase>.+)\s+from\s+(?<source>[\p{L}\p{M} ()-]+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Source();

    #endregion
}
