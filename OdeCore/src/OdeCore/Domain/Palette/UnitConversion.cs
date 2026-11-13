using System.Globalization;
using System.Text.RegularExpressions;

namespace OdeCore.Domain;

/// A measurement a person typed and asked for in another unit of the same
/// kind, such as "5 km in miles", "72 f to c", "convert 2 cups to ml" or
/// "how many ounces in a pound", and its answer, worked out on the device: length, mass, volume,
/// temperature, speed, area, data and duration.
internal sealed partial class UnitConversion {
    #region Types

    /// A unit: its kind, the names a person types for it, what one of it is
    /// in its kind's base unit, the offset temperatures add, and how the
    /// answer names it, once and for any other amount.
    private sealed record Unit(string Kind, string[] Names, double Scale, double Offset, string One, string Many,
        int ChoiceOrder = 0, string? ChoiceAlternative = null, string? ChoiceQualifier = null);

    #endregion

    #region Static Variables

    /// The longest text read as a conversion.
    private const int MaximumLength = 80;

    private static readonly Unit[] Units = [
        new("length", ["mm", "millimeter", "millimeters", "millimetre", "millimetres"], 0.001, 0, "millimeter", "millimeters"),
        new("length", ["cm", "centimeter", "centimeters", "centimetre", "centimetres"], 0.01, 0, "centimeter", "centimeters"),
        new("length", ["m", "meter", "meters", "metre", "metres"], 1, 0, "meter", "meters", ChoiceOrder: 1),
        new("length", ["km", "kilometer", "kilometers", "kilometre", "kilometres", "kms"], 1000, 0, "kilometer", "kilometers", ChoiceOrder: 4),
        new("length", ["in", "inch", "inches", "\""], 0.0254, 0, "inch", "inches", ChoiceOrder: 3),
        new("length", ["ft", "foot", "feet", "'"], 0.3048, 0, "foot", "feet", ChoiceOrder: 2),
        new("length", ["yd", "yard", "yards"], 0.9144, 0, "yard", "yards"),
        new("length", ["mi", "mile", "miles"], 1609.344, 0, "mile", "miles"),
        new("length", ["nmi", "nautical mile", "nautical miles"], 1852, 0, "nautical mile", "nautical miles"),
        new("mass", ["mg", "milligram", "milligrams"], 0.000001, 0, "milligram", "milligrams"),
        new("mass", ["g", "gram", "grams", "gr"], 0.001, 0, "gram", "grams", ChoiceOrder: 3),
        new("mass", ["kg", "kilogram", "kilograms", "kilo", "kilos", "kgs"], 1, 0, "kilogram", "kilograms", ChoiceOrder: 2),
        new("mass", ["t", "tonne", "tonnes", "metric ton", "metric tons"], 1000, 0, "tonne", "tonnes"),
        new("mass", ["oz", "ounce", "ounces"], 0.028349523125, 0, "ounce", "ounces",
            ChoiceAlternative: "fl oz", ChoiceQualifier: "weight"),
        new("mass", ["lb", "lbs", "pound", "pounds"], 0.45359237, 0, "pound", "pounds", ChoiceOrder: 1),
        new("mass", ["st", "stone", "stones"], 6.35029318, 0, "stone", "stone", ChoiceOrder: 4),
        new("volume", ["ml", "milliliter", "milliliters", "millilitre", "millilitres"], 0.001, 0, "milliliter", "milliliters"),
        new("volume", ["cl", "centiliter", "centiliters", "centilitre", "centilitres"], 0.01, 0, "centiliter", "centiliters"),
        new("volume", ["l", "liter", "liters", "litre", "litres"], 1, 0, "liter", "liters", ChoiceOrder: 4),
        // These existing volume factors are US customary, not Imperial or metric cooking measures.
        new("volume", ["tsp", "teaspoon", "teaspoons", "us tsp", "us teaspoon", "us teaspoons"], 0.00492892159375, 0, "US teaspoon", "US teaspoons"),
        new("volume", ["tbsp", "tablespoon", "tablespoons", "us tbsp", "us tablespoon", "us tablespoons"], 0.01478676478125, 0, "US tablespoon", "US tablespoons"),
        new("volume", ["fl oz", "floz", "fluid ounce", "fluid ounces", "us fl oz", "us floz", "us fluid ounce", "us fluid ounces"], 0.0295735295625, 0, "US fluid ounce", "US fluid ounces"),
        new("volume", ["cup", "cups", "us cup", "us cups"], 0.2365882365, 0, "US cup", "US cups", ChoiceOrder: 1),
        new("volume", ["pt", "pint", "pints", "us pt", "us pint", "us pints"], 0.473176473, 0, "US pint", "US pints", ChoiceOrder: 2),
        new("volume", ["qt", "quart", "quarts", "us qt", "us quart", "us quarts"], 0.946352946, 0, "US quart", "US quarts"),
        new("volume", ["gal", "gallon", "gallons", "us gal", "us gallon", "us gallons"], 3.785411784, 0, "US gallon", "US gallons", ChoiceOrder: 3),
        new("temperature", ["c", "°c", "celsius", "centigrade", "degrees celsius", "degrees c"], 1, 273.15, "degree Celsius",
            "degrees Celsius", ChoiceOrder: 1),
        new("temperature", ["f", "°f", "fahrenheit", "degrees fahrenheit", "degrees f"], 5.0 / 9, 459.67 * 5 / 9, "degree Fahrenheit",
            "degrees Fahrenheit", ChoiceOrder: 2),
        new("temperature", ["k", "kelvin", "kelvins"], 1, 0, "kelvin", "kelvins", ChoiceOrder: 3),
        new("speed", ["m/s", "mps", "meters per second", "metres per second"], 1, 0, "meter per second", "meters per second", ChoiceOrder: 3),
        new("speed", ["km/h", "kmh", "kph", "kmph", "kilometers per hour", "kilometres per hour"], 1000.0 / 3600, 0, "kilometer per hour",
            "kilometers per hour", ChoiceOrder: 1),
        new("speed", ["mph", "miles per hour"], 1609.344 / 3600, 0, "mile per hour", "miles per hour", ChoiceOrder: 2),
        new("speed", ["kn", "kt", "knot", "knots"], 1852.0 / 3600, 0, "knot", "knots", ChoiceOrder: 4),
        new("area", ["m2", "m²", "sq m", "square meter", "square meters", "square metre", "square metres"], 1, 0, "square meter",
            "square meters", ChoiceOrder: 1),
        new("area", ["km2", "km²", "sq km", "square kilometer", "square kilometers", "square kilometre", "square kilometres"], 1_000_000, 0,
            "square kilometer", "square kilometers"),
        new("area", ["ft2", "ft²", "sq ft", "sqft", "square foot", "square feet"], 0.09290304, 0, "square foot", "square feet", ChoiceOrder: 2),
        new("area", ["mi2", "mi²", "sq mi", "square mile", "square miles"], 2_589_988.110336, 0, "square mile", "square miles"),
        new("area", ["ha", "hectare", "hectares"], 10_000, 0, "hectare", "hectares", ChoiceOrder: 4),
        new("area", ["acre", "acres", "ac"], 4046.8564224, 0, "acre", "acres", ChoiceOrder: 3),
        new("data", ["b", "byte", "bytes"], 1, 0, "byte", "bytes"),
        new("data", ["kb", "kilobyte", "kilobytes"], 1e3, 0, "kilobyte", "kilobytes"),
        new("data", ["mb", "megabyte", "megabytes"], 1e6, 0, "megabyte", "megabytes", ChoiceOrder: 1),
        new("data", ["gb", "gigabyte", "gigabytes"], 1e9, 0, "gigabyte", "gigabytes", ChoiceOrder: 2),
        new("data", ["tb", "terabyte", "terabytes"], 1e12, 0, "terabyte", "terabytes"),
        new("data", ["kib", "kibibyte", "kibibytes"], 1024, 0, "kibibyte", "kibibytes", ChoiceOrder: 3),
        new("data", ["mib", "mebibyte", "mebibytes"], 1_048_576, 0, "mebibyte", "mebibytes", ChoiceOrder: 4),
        new("data", ["gib", "gibibyte", "gibibytes"], 1_073_741_824, 0, "gibibyte", "gibibytes"),
        new("data", ["tib", "tebibyte", "tebibytes"], 1_099_511_627_776, 0, "tebibyte", "tebibytes"),
        new("duration", ["s", "sec", "secs", "second", "seconds"], 1, 0, "second", "seconds"),
        new("duration", ["min", "mins", "minute", "minutes"], 60, 0, "minute", "minutes", ChoiceOrder: 1),
        new("duration", ["h", "hr", "hrs", "hour", "hours"], 3600, 0, "hour", "hours", ChoiceOrder: 2),
        new("duration", ["d", "day", "days"], 86_400, 0, "day", "days", ChoiceOrder: 3),
        new("duration", ["wk", "wks", "week", "weeks"], 604_800, 0, "week", "weeks", ChoiceOrder: 4),
    ];

    #endregion

    #region Variables

    /// The amount as typed.
    public double Amount { get; }

    /// The answer, in the asked unit.
    public double Value { get; }

    /// The answer as the card shows and copies it: about four significant
    /// digits, without trailing zeros.
    public string Answer => Format(Value);

    /// What was asked, written out, such as "5 kilometers".
    public string Asked => $"{Format(Amount)} {Named(from, Amount)}";

    /// The answer with its unit, such as "3.107 miles".
    public string Answered => $"{Answer} {Named(to, Value)}{(qualifier is null ? "" : $" ({qualifier})")}";

    private readonly Unit from;
    private readonly Unit to;
    private readonly string? qualifier;

    #endregion

    #region Constructors

    private UnitConversion(double amount, Unit from, Unit to, string? qualifier = null) {
        Amount = amount;
        this.from = from;
        this.to = to;
        this.qualifier = qualifier;
        double baseValue = amount * from.Scale + from.Offset;
        Value = (baseValue - to.Offset) / to.Scale;
    }

    #endregion

    #region Actions - Reading

    /// The conversion `typed` asks for, or null when it names no amount, no
    /// two known units of the same kind, or the same unit twice.
    public static UnitConversion? Of(string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        string text = typed.Trim().ToLowerInvariant();
        if (text.Length is 0 or > MaximumLength) return null;
        var match = Asking().Match(text);
        if (!match.Success) match = HowMany().Match(text);
        if (!match.Success) return null;
        if (ReadAmount(match) is not { } amount) return null;
        if (Find(match.Groups["from"].Value) is not { } from || Find(match.Groups["to"].Value) is not { } to || from == to
            || from.Kind != to.Kind)
            return null;
        var conversion = new UnitConversion(amount, from, to);
        return double.IsFinite(conversion.Value) ? conversion : null;
    }

    /// The amount in either conversion grammar; an article means one.
    private static double? ReadAmount(Match match) => match.Groups["amount"].Success ? ReadAmount(match.Groups["amount"].Value) : 1;

    /// `written` as a number, or null when its separators do not read.
    /// Digits may be grouped in threes by a space or a comma, as "1,000" and
    /// "1 000", with a point before any decimals, as "1,000.5". A comma before
    /// any other run of digits, or after a lone zero, is a decimal comma, as
    /// "0,5" and "3,14"; a point is only ever the decimal point, so "1.000"
    /// is one.
    private static double? ReadAmount(string written) {
        string sign = written.Length > 0 && written[0] is '-' or '+' ? written[..1] : "";
        string number = written[sign.Length..];
        int point = number.IndexOf('.');
        string whole = point < 0 ? number : number[..point];
        string fraction = point < 0 ? "" : number[(point + 1)..];
        if (fraction.AsSpan().IndexOfAny(" ,.") >= 0) return null;
        var groups = whole.Split(' ', ',');
        if (groups.Length > 1) {
            bool decimalComma = groups.Length == 2 && whole.Contains(',') && (groups[1].Length != 3 || groups[0] == "0");
            if (decimalComma) {
                if (fraction.Length > 0) return null;
                (whole, fraction) = (groups[0], groups[1]);
            } else if (groups[0].Length > 3 || groups.Skip(1).Any(group => group.Length != 3)) {
                return null;
            } else {
                whole = string.Concat(groups);
            }
        }
        string invariant = fraction.Length == 0 ? sign + whole : $"{sign}{whole}.{fraction}";
        return double.TryParse(invariant, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture,
            out double amount) && double.IsFinite(amount) ? amount : null;
    }

    /// The unit `name` names, ignoring a leading "a" or "an" and spaces
    /// around it, or null.
    private static Unit? Find(string name) {
        string trimmed = name.Trim();
        if (trimmed.StartsWith("a ", StringComparison.Ordinal)) trimmed = trimmed[2..];
        else if (trimmed.StartsWith("an ", StringComparison.Ordinal)) trimmed = trimmed[3..];
        if (trimmed.StartsWith("degrees ", StringComparison.Ordinal) && trimmed.Length <= "degrees ".Length + 1)
            trimmed = trimmed["degrees ".Length..];
        return Units.FirstOrDefault(unit => unit.Names.Contains(trimmed, StringComparer.Ordinal));
    }

    private static string Named(Unit unit, double amount) => Math.Abs(amount) == 1 ? unit.One : unit.Many;

    /// `value` to about four significant digits, without trailing zeros or
    /// a negative zero.
    private static string Format(double value) {
        if (value == 0) return "0";
        double magnitude = Math.Floor(Math.Log10(Math.Abs(value)));
        int decimals = (int)Math.Clamp(3 - magnitude, 0, 6);
        double rounded = Math.Round(value, decimals, MidpointRounding.AwayFromZero);
        return rounded == 0 ? "0" : rounded.ToString("0.######", CultureInfo.InvariantCulture);
    }

    /// The amount is digits with any run of space, comma or point groups,
    /// which `ReadAmount` reads; a unit never starts with a digit, so a group
    /// never takes the start of one.
    [GeneratedRegex(@"^(?:convert\s+)?(?<amount>[-+]?\d+(?:[ .,]\d+)*)\s*(?<from>[a-z°""'/²0-9 ]+?)\s+(?:in|to|into|as)\s+(?<to>[a-z°""'/²0-9 ]+?)\s*\??$",
        RegexOptions.CultureInvariant)]
    private static partial Regex Asking();

    /// "how many ounces in a pound" or "how many cups are in 2 gallons".
    [GeneratedRegex(@"^how many\s+(?<to>[a-z°""'/²0-9 ]+?)\s+(?:are\s+|is\s+)?in\s+(?:(?<amount>[-+]?\d+(?:[ .,]\d+)*)\s*|an?\s+|one\s+)(?<from>[a-z°""'/²0-9 ]+?)\s*\??$",
        RegexOptions.CultureInvariant)]
    private static partial Regex HowMany();

    #endregion
}
