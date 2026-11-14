using System.Globalization;
using System.Text.RegularExpressions;

namespace OdeCore.Domain;

/// Arithmetic a person typed into the palette and its answer: numbers with
/// `+ − × ÷ ^ %`, parentheses, scientific notation and a leading minus,
/// with at least one operator, or a whole percentage phrase such as
/// `20% of 80` or `20% off 80`. A bare number or arbitrary prose is never a
/// calculation. Powers bind before signs and associate to the right.
public sealed partial class Calculation {
    #region Static Variables

    /// The longest text the palette reads as a calculation.
    private const int MaximumLength = 128;

    /// The deepest parentheses the palette follows.
    private const int MaximumDepth = 32;

    #endregion

    #region Variables

    /// The expression as typed, trimmed.
    public string Expression { get; }

    /// The answer.
    public double Value { get; private init; }

    /// The answer as the palette shows and copies it: up to twelve
    /// significant digits, without trailing zeros.
    public string Answer => Value.ToString("G12", CultureInfo.InvariantCulture);

    private readonly string text;
    private int position;
    private int depth;
    private bool operated;
    private bool? percentageDiscount;

    #endregion

    #region Constructors

    private Calculation(string expression) {
        Expression = expression;
        text = expression;
    }

    #endregion

    #region Actions - Reading

    /// The calculation `typed` spells, or null when it is not arithmetic, has
    /// no operator, or has no finite answer.
    public static Calculation? Of(string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        string trimmed = typed.Trim();
        if (trimmed.Length is 0 or > MaximumLength || !trimmed.Any(char.IsAsciiDigit)) return null;
        var calculation = new Calculation(trimmed);
        try {
            double value = calculation.Percentage() ?? calculation.Sum();
            calculation.SkipSpace();
            if (calculation.position != trimmed.Length || !calculation.operated || !double.IsFinite(value)) return null;
            return new Calculation(trimmed) { Value = value == 0 ? 0 : value, percentageDiscount = calculation.percentageDiscount };
        } catch (FormatException) {
            return null;
        }
    }

    /// Grounded operands alone cannot authorize dropping or changing an explicit percentage operation.
    internal bool PreservesPercentage(string source) {
        if (!PercentageMarker().IsMatch(source)) return true;
        var operations = PercentageRequest().Matches(source);
        return operations.Count == 1 && percentageDiscount is not null
            && percentageDiscount == operations[0].Groups["operation"].Value.Equals("off", StringComparison.OrdinalIgnoreCase);
    }

    [GeneratedRegex(@"%|\bpercent(?:age)?\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PercentageMarker();

    [GeneratedRegex(@"(?:%|\bpercent(?:age)?\b)\s+(?<operation>of|off)\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PercentageRequest();

    /// Only two numeric literals and one percentage operation, not an
    /// expression embedded in prose. "Off" subtracts the percentage of the
    /// amount from that amount; neither phrase changes binary remainder.
    private double? Percentage() {
        int percent = text.IndexOf('%', StringComparison.Ordinal);
        if (percent < 0) return null;
        position = percent + 1;
        bool discount = TakeWord("off");
        if (!discount && !TakeWord("of")) {
            position = 0;
            return null;
        }
        int amountStart = position;
        position = 0;
        double rate = SignedNumber();
        SkipSpace();
        if (position != percent) throw new FormatException();
        position = amountStart;
        double amount = SignedNumber();
        percentageDiscount = discount;
        operated = true;
        double portion = Finite(rate / 100 * amount);
        return discount ? Finite(amount - portion) : portion;
    }

    private double SignedNumber() {
        SkipSpace();
        bool negative = Take('-') || Take('−');
        if (!negative) Take('+');
        double value = Number();
        return negative ? -value : value;
    }

    /// A word needs whitespace on both sides, so "offer" is still a search.
    private bool TakeWord(string word) {
        int start = position;
        SkipSpace();
        if (position > start && text.AsSpan(position).StartsWith(word, StringComparison.OrdinalIgnoreCase)) {
            int end = position + word.Length;
            if (end < text.Length && char.IsWhiteSpace(text[end])) {
                position = end;
                return true;
            }
        }
        position = start;
        return false;
    }

    private double Sum() {
        double value = Product();
        while (true) {
            SkipSpace();
            if (Take('+')) value += Product();
            else if (Take('-') || Take('−')) value -= Product();
            else return value;
            value = Finite(value);
            operated = true;
        }
    }

    private double Product() {
        double value = Unary();
        while (true) {
            SkipSpace();
            if (Take('*') || Take('×') || Take('x')) value *= Unary();
            else if (Take('/') || Take('÷')) value /= Unary();
            else if (Take('%')) value %= Unary();
            else return value;
            value = Finite(value);
            operated = true;
        }
    }

    private double Power() {
        double value = Primary();
        SkipSpace();
        if (!Take('^')) return value;
        operated = true;
        return Finite(Math.Pow(value, Unary()));
    }

    private double Unary() {
        SkipSpace();
        if (Take('-') || Take('−')) {
            operated = true;
            return -Unary();
        }
        if (Take('+')) return Unary();
        return Power();
    }

    private double Primary() {
        SkipSpace();
        if (Take('(')) {
            if (++depth > MaximumDepth) throw new FormatException();
            double value = Sum();
            SkipSpace();
            if (!Take(')')) throw new FormatException();
            depth--;
            return value;
        }
        return Number();
    }

    private double Number() {
        SkipSpace();
        int start = position;
        while (position < text.Length && (char.IsAsciiDigit(text[position]) || text[position] == '.')) position++;
        if (Take('e') || Take('E')) {
            if (!Take('+')) Take('-');
            int exponent = position;
            while (position < text.Length && char.IsAsciiDigit(text[position])) position++;
            if (position == exponent) throw new FormatException();
        }
        if (position == start || !double.TryParse(text.AsSpan(start, position - start),
            NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent, CultureInfo.InvariantCulture, out double value)
            || !double.IsFinite(value)) throw new FormatException();
        return value;
    }

    /// Reject undefined arithmetic at the operation that produced it, before
    /// a later operation can turn NaN or infinity into a finite-looking answer.
    private static double Finite(double value) => double.IsFinite(value) ? value : throw new FormatException();

    private bool Take(char expected) {
        if (position >= text.Length || text[position] != expected) return false;
        position++;
        return true;
    }

    private void SkipSpace() {
        while (position < text.Length && char.IsWhiteSpace(text[position])) position++;
    }

    #endregion
}
