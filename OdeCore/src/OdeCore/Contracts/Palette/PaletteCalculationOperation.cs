using System.Globalization;

namespace OdeCore.Contracts;

/// Bounded model-selected operations. Operand representations are normalized only by core.
public sealed class PaletteCalculationOperation {
    #region Static Variables

    public static readonly PaletteCalculationOperation Add = new("add", "+");
    public static readonly PaletteCalculationOperation Subtract = new("subtract", "-");
    public static readonly PaletteCalculationOperation Multiply = new("multiply", "*");
    public static readonly PaletteCalculationOperation Divide = new("divide", "/");
    public static readonly PaletteCalculationOperation PercentOf = new("percentOf", "% of", hasPercentageRate: true);
    public static readonly PaletteCalculationOperation PercentOff = new("percentOff", "% off", hasPercentageRate: true);
    public static IReadOnlyList<PaletteCalculationOperation> All { get; } = [Add, Subtract, Multiply, Divide, PercentOf, PercentOff];

    #endregion

    #region Variables

    public string Name { get; }
    private readonly string symbol;
    private readonly bool hasPercentageRate;

    #endregion

    #region Constructors

    private PaletteCalculationOperation(string name, string symbol, bool hasPercentageRate = false) {
        Name = name;
        this.symbol = symbol;
        this.hasPercentageRate = hasPercentageRate;
    }

    #endregion

    #region Actions - Resolution

    public static PaletteCalculationOperation? Named(string? name) => All.FirstOrDefault(operation => operation.Name == name);

    internal string? Expression(string source, string? leftQuote, string? rightQuote) {
        leftQuote = RateNumber(leftQuote);
        if (leftQuote is null || rightQuote is null
            || (PaletteInterpretation.QuotedNumber(source, leftQuote) ?? PaletteInterpretation.ReadNumber(leftQuote)) is not { } left
            || (PaletteInterpretation.QuotedNumber(source, rightQuote) ?? PaletteInterpretation.ReadNumber(rightQuote)) is not { } right) return null;
        // Parsing a representation is not authorization: Calculate still matches each signed
        // value to one unused complete source-number span and checks percentage roles.
        return $"{left.ToString("R", CultureInfo.InvariantCulture)} {symbol} {right.ToString("R", CultureInfo.InvariantCulture)}";
    }

    /// Only a percentage operation's rate may carry one trailing marker. The
    /// remainder must still parse as one number and pass Calculate's source binding.
    private string? RateNumber(string? quote) {
        if (!hasPercentageRate || quote is null) return quote;
        string text = quote.Trim();
        if (text.EndsWith('%')) return text[..^1].TrimEnd();
        const string marker = "percent";
        return text.Length > marker.Length && text.EndsWith(marker, StringComparison.OrdinalIgnoreCase)
            && char.IsWhiteSpace(text[^(marker.Length + 1)]) ? text[..^marker.Length].TrimEnd() : quote;
    }

    #endregion
}
