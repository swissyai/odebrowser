using System.Text.RegularExpressions;

namespace OdeCore.Domain;

internal sealed partial class UnitConversion {
    #region Static Variables

    private const int MaximumChoices = 4;

    #endregion

    #region Actions - Choices

    /// A few useful completions of an explicit "how many … in a …" question,
    /// from the same unit catalog and amount grammar as complete conversions.
    /// The catalog's order is curated, not inferred from usage. A typed prefix
    /// filters all compatible units; an exact unit, even an incompatible one,
    /// is a complete question and must not be silently reinterpreted.
    public static IReadOnlyList<UnitConversion> Choices(string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        string text = typed.Trim().ToLowerInvariant();
        if (text.Length is 0 or > MaximumLength) return [];
        var match = HowManyPrefix().Match(text);
        if (!match.Success || ReadAmount(match) is not { } amount || Find(match.Groups["to"].Value) is not { } to) return [];
        string prefix = match.Groups["from"].Value.Trim();
        if (Find(prefix) is not null) return [];

        // Only incomplete questions may offer the separate fluid interpretation
        // of "oz". Completed ounces-to-cup questions still require clarification.
        var alternative = to.ChoiceAlternative is { } name ? Find(name) : null;
        List<UnitConversion> choices = [];
        foreach (var from in Units.OrderBy(unit => unit.ChoiceOrder > 0 ? unit.ChoiceOrder : int.MaxValue)) {
            var target = from.Kind == to.Kind ? to : alternative is not null && from.Kind == alternative.Kind ? alternative : null;
            if (target is null || from == target) continue;
            if (prefix.Length == 0 ? from.ChoiceOrder == 0 : !from.Names.Any(name => name.StartsWith(prefix, StringComparison.Ordinal)))
                continue;
            var conversion = new UnitConversion(amount, from, target, target.ChoiceQualifier);
            if (!double.IsFinite(conversion.Value)) continue;
            choices.Add(conversion);
            if (choices.Count == MaximumChoices) break;
        }
        return choices;
    }

    [GeneratedRegex(@"^how many\s+(?<to>[a-z°""'/²0-9 ]+?)\s+(?:are\s+|is\s+)?in\s+(?:(?<amount>[-+]?\d+(?:[.,]\d+)?)\s*|an?\b\s*|one\b\s*)(?<from>[a-z°""'/²0-9 ]*)$",
        RegexOptions.CultureInvariant)]
    private static partial Regex HowManyPrefix();

    #endregion
}
