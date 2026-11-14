using System.Globalization;
using System.Text.RegularExpressions;

using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Untrusted model-selected inputs. Only the core's checked tools produce values.
public sealed partial record PaletteInterpretation(PaletteInterpretationKind Kind, string? Expression,
    string? Amount, string? FromUnit, string? ToUnit, string? Ingredient) {
    #region Types

    private sealed record GroundedNumber(string Quote, double Value, int Start);

    #endregion

    #region Static Variables

    private static readonly string[] SmallNumbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"];
    private static readonly string[] Tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"];

    #endregion

    #region Actions - Resolution

    internal PaletteCard? Resolve(PaletteGenerativeLookup lookup, PalettePreferences preferences) {
        return Kind.Resolve(this, lookup, preferences);
    }

    internal PaletteCard? Calculate(string source) {
        if (Expression is null || Expression.Length > 128) return null;
        var literals = NumericLiteral().Matches(Expression);
        var numbers = GroundedNumbers(source, Expression, literals);
        if (numbers is null || numbers.Count == 0 || numbers.Count > 16 || literals.Count != numbers.Count) return null;
        if (Calculation.Of(Expression) is not { } calculation) return null;
        return Card(PaletteCardKind.Calculation, calculation.Answer, $"{calculation.Expression} =", calculation.Answer);
    }

    /// Native expression-only schemas do not need a second parallel operand array.
    /// Match each literal to one unused bounded source number, including practical number words.
    private static IReadOnlyList<GroundedNumber>? GroundedNumbers(string source, string expression, MatchCollection literals) {
        if (literals.Count is 0 or > 16) return null;
        var candidates = SourceNumbers(source).Where(number => !number.Quote.Equals("a", StringComparison.OrdinalIgnoreCase)
            && !number.Quote.Equals("an", StringComparison.OrdinalIgnoreCase)).ToList();
        List<GroundedNumber> result = [];
        foreach (Match literal in literals) {
            if (OperandValue(expression, literal) is not { } value) return null;
            int index = candidates.FindIndex(candidate => candidate.Value == value);
            if (index < 0) return null;
            result.Add(candidates[index]);
            candidates.RemoveAt(index);
        }
        return result;
    }

    /// Distinguish unary signs from binary subtraction without changing the tool grammar.
    private static double? OperandValue(string expression, Match literal) {
        int position = literal.Index - 1;
        List<char> signs = [];
        while (position >= 0) {
            char character = expression[position];
            if (char.IsWhiteSpace(character)) { position--; continue; }
            if (character is not ('+' or '-' or '−')) break;
            signs.Add(character);
            position--;
        }
        // The leftmost sign after a number/closing parenthesis is binary.
        int count = signs.Count - (position >= 0 && (char.IsAsciiDigit(expression[position]) || expression[position] == ')') ? 1 : 0);
        if (!double.TryParse(literal.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out double value)
            || !double.IsFinite(value)) return null;
        for (int index = 0; index < count; index++)
            if (signs[index] is '-' or '−') value = -value;
        return value;
    }

    /// Read whole numeric spans once for both tools. Unsupported composite syntax
    /// stays one rejected span, so its smaller components cannot become operands.
    private static IReadOnlyList<GroundedNumber> SourceNumbers(string source) {
        var tokens = SourceToken().Matches(source);
        List<GroundedNumber> result = [];
        for (int index = 0; index < tokens.Count; index++) {
            var first = tokens[index];
            bool signWord = first.Value.ToLowerInvariant() is "minus" or "plus";
            if (signWord && result.Count > 0 && FollowsNumber(source, first.Index, result[^1])) continue;
            if (!NumberToken(first.Value) && !signWord) continue;
            index = SourceNumberEnd(source, tokens, index);
            string quote = source[first.Index..(tokens[index].Index + tokens[index].Length)];
            if (ReadNumber(quote) is { } value) result.Add(new(quote, value, first.Index));
        }
        return result;
    }

    private static bool FollowsNumber(string source, int position, GroundedNumber previous) =>
        source[(previous.Start + previous.Quote.Length)..position].All(char.IsWhiteSpace);

    private static int SourceNumberEnd(string source, MatchCollection tokens, int index) {
        int start = tokens[index].Index;
        int end = start + tokens[index].Length;
        while (index + 1 < tokens.Count) {
            var next = tokens[index + 1];
            string gap = source[end..next.Index];
            if (gap.Length == 0 || !gap.All(character => char.IsWhiteSpace(character) || character == '-')) break;
            if (next.Value.Equals("and", StringComparison.OrdinalIgnoreCase) && ReadNumber(source[start..end]) is null
                && index + 2 < tokens.Count && NumberToken(tokens[index + 2].Value)) {
                index++;
                end = next.Index + next.Length;
                continue;
            }
            if (!NumberToken(next.Value)) break;
            index++;
            end = next.Index + next.Length;
        }
        return index;
    }

    private static bool NumberToken(string token) => token.Any(char.IsNumber) || ReadNumber(token.TrimStart('+', '-', '−', ' ')) is not null
        || token.ToLowerInvariant() is "negative" or "positive" or "hundred" or "thousand" or "million" or "billion"
            or "trillion" or "quadrillion";

    internal static double? QuotedNumber(string source, string quote, string? quantity = null) => SourceNumbers(source)
        .FirstOrDefault(number => number.Quote.Equals(quote, StringComparison.OrdinalIgnoreCase)
            && (quantity is null || source.AsSpan(number.Start).StartsWith(quantity, StringComparison.OrdinalIgnoreCase)))?.Value;

    internal static bool HasNumber(string source) => SourceToken().Matches(source).Any(token =>
        token.Value.ToLowerInvariant() is not ("a" or "an" or "negative" or "positive") && NumberToken(token.Value));

    [GeneratedRegex(@"(?<![\p{L}\p{N}])(?:[-+−]\s*)*(?:(?:\p{N}+(?:[.,_'’]\p{N}+)*|[.,]\p{N}+)(?:[eE][-+−]?\p{N}+)?|[\p{L}]+(?:-[\p{L}]+)?)", RegexOptions.CultureInvariant)]
    private static partial Regex SourceToken();

    internal static PaletteCard Card(PaletteCardKind kind, string title, string subtitle, string? value = null) =>
        new(kind, title, subtitle, Body: null, value, Address: null, Term: null, Clock: null, Image: null, Credit: null,
            CreditAddress: null, License: null, LicenseAddress: null);

    internal static PaletteCard Clarification(string message) => Card(PaletteCardKind.Clarification, message, "Ode · On device");

    internal static bool Quoted(string source, string? quote) => !string.IsNullOrWhiteSpace(quote) && quote.Length <= 80
        && !quote.Any(char.IsControl) && QuoteMatch(source, quote).Success;

    private static Match QuoteMatch(string source, string quote) => Regex.Match(source,
        @"(?<![\p{L}\p{N}])" + Regex.Escape(quote) + @"(?![\p{L}\p{N}])", RegexOptions.CultureInvariant);

    /// Bounded number words, not model-supplied normalization. Unsupported words fail closed.
    internal static double? ReadNumber(string quote) {
        if (quote.Length > 80) return null;
        if (UnitConversion.ReadAmount(quote) is { } numeric) return numeric;
        string text = quote.Trim().ToLowerInvariant();
        if (text.Length == 0 || !char.IsAsciiLetter(text[0])) return null;
        if (text is "a" or "an") return 1;
        int small = Array.IndexOf(SmallNumbers, text);
        if (small >= 0) return small;
        string[] words = text.Replace('-', ' ').Split(' ', StringSplitOptions.RemoveEmptyEntries);
        int tens = words.Length > 0 ? Array.IndexOf(Tens, words[0]) : -1;
        if (tens < 0 || words.Length > 2) return null;
        if (words.Length == 1) return (tens + 2) * 10;
        int ones = Array.IndexOf(SmallNumbers, words[1]);
        return ones is > 0 and < 10 ? (tens + 2) * 10 + ones : null;
    }

    [GeneratedRegex(@"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", RegexOptions.CultureInvariant)]
    private static partial Regex NumericLiteral();

    #endregion
}
