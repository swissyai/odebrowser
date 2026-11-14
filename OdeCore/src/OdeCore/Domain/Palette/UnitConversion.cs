using System.Globalization;
using System.Text.RegularExpressions;

using OdeCore.Contracts;

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

    private sealed record SourceUnit(Unit Unit, int Start, int Length);

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
        new("volume", ["fl oz", "fl. oz", "fl. oz.", "floz", "fluid ounce", "fluid ounces", "us fl oz", "us fl. oz", "us fl. oz.", "us floz", "us fluid ounce", "us fluid ounces"], 0.0295735295625, 0, "US fluid ounce", "US fluid ounces"),
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

    // One longest-first catalog matcher owns complete unit spans, including qualified aliases.
    // Apostrophe-linked word fragments are not units; surrounding quotation marks still are allowed.
    private static readonly Regex UnitNames = new(@"(?<![\p{L}\p{N}])(?<![\p{L}\p{N}]['’])(?:"
        + string.Join("|", Units.SelectMany(unit => unit.Names).OrderByDescending(name => name.Length).Select(Regex.Escape))
        + @")(?![\p{L}\p{N}])(?!['’][\p{L}\p{N}])", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

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

    /// The conversion `typed` asks for, or null when it names no two known
    /// units of the same kind, or the same unit twice. A bare unit ratio uses one.
    public static UnitConversion? Of(string typed) {
        if (ReadRequest(typed) is not { } request || request.From.Kind != request.To.Kind) return null;
        var conversion = new UnitConversion(request.Amount, request.From, request.To);
        return double.IsFinite(conversion.Value) ? conversion : null;
    }

    /// Mass and volume require an ingredient's density, never an assumed water
    /// equivalent. This classification produces no numeric conversion.
    public static bool NeedsIngredient(string typed) => ReadRequest(typed) is { } request
        && (request.From.Kind == "mass" && request.To.Kind == "volume"
            || request.From.Kind == "volume" && request.To.Kind == "mass");

    internal static PaletteCard IngredientClarification(string source) =>
        ReadRequest(source) is { } request && (request.From.ChoiceAlternative is not null || request.To.ChoiceAlternative is not null)
            ? PaletteInterpretation.Clarification("Do you mean weight ounces or US fluid ounces?")
            : PaletteInterpretation.Clarification("Which ingredient?");

    /// Resolve source-grounded fields directly against the existing catalog, never synthesized prose.
    internal static PaletteCard? Resolve(string source, string? amountQuote, string? fromQuote, string? toQuote, string? ingredient) {
        if (ingredient is not null && !PaletteInterpretation.Quoted(source, ingredient)) return null;
        if (Regional().IsMatch(source))
            return PaletteInterpretation.Clarification("Imperial and regional cooking measures aren’t supported.");
        var sourceUnits = SourceUnits(source);
        var from = QuotedUnit(sourceUnits, fromQuote);
        var to = QuotedUnit(sourceUnits, toQuote);
        if (from is null || to is null || from == to && sourceUnits.Count(unit => unit.Unit == from) < 2) return null;
        return from.Kind != to.Kind ? ResolveDimensions(from, to, ingredient) : ResolveAmount(source, amountQuote, from, to, sourceUnits);
    }

    private static PaletteCard? ResolveDimensions(Unit from, Unit to, string? ingredient) {
        if (from.Kind is not ("mass" or "volume") || to.Kind is not ("mass" or "volume")) return null;
        if (from.ChoiceAlternative is not null || to.ChoiceAlternative is not null)
            return PaletteInterpretation.Clarification("Do you mean weight ounces or US fluid ounces?");
        return PaletteInterpretation.Clarification(ingredient is null
            ? "Which ingredient?"
            : $"Use the weight per measure for {ingredient}.");
    }

    private static PaletteCard? ResolveAmount(string source, string? amountQuote, Unit from, Unit to,
        IReadOnlyList<SourceUnit> sourceUnits) {
        if (amountQuote is null && (from.Offset != 0 || to.Offset != 0))
            return PaletteInterpretation.Clarification("What temperature are you converting?");
        double? amount = DirectedAmount(source, amountQuote, from, to, sourceUnits);
        if (amount is null) return null;
        var conversion = new UnitConversion(amount.Value, from, to);
        return double.IsFinite(conversion.Value)
            ? PaletteInterpretation.Card(PaletteCardKind.Conversion, conversion.Answered, $"{conversion.Asked} =", conversion.Answer) : null;
    }

    /// A model may use a catalog alias, but that exact unit must also be present in the source.
    private static Unit? QuotedUnit(IReadOnlyList<SourceUnit> sourceUnits, string? proposed) {
        if (proposed is null || proposed.Length > 80 || Find(proposed.ToLowerInvariant()) is not { } unit) return null;
        return sourceUnits.Any(occurrence => occurrence.Unit == unit) ? unit : null;
    }

    private static IReadOnlyList<SourceUnit> SourceUnits(string source) {
        string text = source.ToLowerInvariant();
        return UnitNames.Matches(text).Where(match => !UnitQualifier().IsMatch(text[..match.Index]))
            .Select(match => new SourceUnit(Find(match.Value)!, match.Index, match.Length)).ToArray();
    }

    // A qualifier not consumed by the full catalog alias cannot be silently discarded.
    [GeneratedRegex(@"\b(?:fluid|nautical|square|cubic|troy|survey|metric|us)\s+$", RegexOptions.CultureInvariant)]
    private static partial Regex UnitQualifier();

    /// A single whole-source quantity must adjoin its source unit, and a directed
    /// clause must name the target. Unit membership alone never authorizes direction.
    private static double? DirectedAmount(string source, string? quote, Unit from, Unit to, IReadOnlyList<SourceUnit> units) {
        var quantities = units.Select(unit => (Unit: unit, Number: PaletteInterpretation.NumberBefore(source, unit.Start)))
            .Where(quantity => quantity.Number is not null).ToArray();
        if (quantities.Length != 1 || quantities[0].Unit.Unit != from) return null;
        var origin = quantities[0].Unit;
        var number = quantities[0].Number!.Value;
        int end = origin.Start + origin.Length;
        var targets = units.Where(unit => unit.Start >= end && DirectedUnit().IsMatch(source[end..unit.Start])).ToArray();
        if (targets.Length != 1 || targets[0].Unit != to) return null;
        var target = targets[0];
        int directionStart = end + DirectedUnit().Match(source[end..target.Start]).Index;
        // The catalog also recognizes the connector "in" as inches. Only that
        // exact connector occurrence may sit between the two requested units.
        if (units.Any(unit => unit != origin && unit != target
            && !(unit.Start == directionStart && source.Substring(unit.Start, unit.Length).Equals("in", StringComparison.OrdinalIgnoreCase))))
            return null;
        return QuotedQuantity(source, quote, from, to, number, end);
    }

    private static double? QuotedQuantity(string source, string? quote, Unit from, Unit to,
        (string Quote, double Value, int Start) number, int end) {
        bool article = number.Quote.Equals("a", StringComparison.OrdinalIgnoreCase)
            || number.Quote.Equals("an", StringComparison.OrdinalIgnoreCase);
        if (article && (quote is null || quote == "1") && from.Offset == 0 && to.Offset == 0) return 1;
        string quantity = source[number.Start..end];
        return quote is not null && (quote.Equals(number.Quote, StringComparison.OrdinalIgnoreCase)
            || quote.Equals(quantity, StringComparison.OrdinalIgnoreCase)) ? number.Value : null;
    }

    [GeneratedRegex(@"\b(?:in|into|to|as)\s+$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex DirectedUnit();

    internal static bool IsBareMeasurement(string source) {
        var match = BareMeasurement().Match(source.Trim().ToLowerInvariant());
        return match.Success && ReadAmount(match.Groups["amount"].Value) is not null && Find(match.Groups["unit"].Value) is not null;
    }

    [GeneratedRegex(@"^(?<amount>[-+]?\d+(?:[ .,]\d+)*)\s*(?<unit>[a-z°²0-9 ]+)$", RegexOptions.CultureInvariant)]
    private static partial Regex BareMeasurement();

    internal static bool MentionsUnit(string source) => ReadRequest(source) is not null || UnitNames.Matches(source).Any(match =>
        match.Length > 1 && !match.Value.Equals("in", StringComparison.OrdinalIgnoreCase));

    [GeneratedRegex(@"\b(?:imperial|british|uk|australian|metric\s+(?:cup|spoon|teaspoon|tablespoon))\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Regional();

    private static (double Amount, Unit From, Unit To)? ReadRequest(string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        string text = typed.Trim().ToLowerInvariant();
        if (text.Length is 0 or > MaximumLength) return null;
        var match = HowMany().Match(text);
        bool direct = !match.Success;
        if (direct) match = Asking().Match(text);
        if (!match.Success || ReadAmount(match) is not { } amount) return null;
        if (Find(match.Groups["from"].Value) is not { } from || Find(match.Groups["to"].Value) is not { } to || from == to)
            return null;
        // An offset temperature is not a unit ratio; require its actual amount.
        if (direct && !match.Groups["amount"].Success && (from.Offset != 0 || to.Offset != 0)) return null;
        return (amount, from, to);
    }

    /// The amount in either conversion grammar; an article means one.
    private static double? ReadAmount(Match match) => match.Groups["amount"].Success ? ReadAmount(match.Groups["amount"].Value) : 1;

    /// `written` as a number, or null when its separators do not read.
    /// Digits may be grouped in threes by a space or a comma, as "1,000" and
    /// "1 000", with a point before any decimals, as "1,000.5". A comma before
    /// any other run of digits, or after a lone zero, is a decimal comma, as
    /// "0,5" and "3,14"; a point is only ever the decimal point, so "1.000"
    /// is one.
    internal static double? ReadAmount(string written) {
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
    [GeneratedRegex(@"^(?:convert\s+)?(?:(?<amount>[-+]?\d+(?:[ .,]\d+)*)\s*)?(?<from>[a-z°""'/²0-9 ]+?)\s+(?:in|to|into|as)\s+(?<to>[a-z°""'/²0-9 ]+?)\s*\??$",
        RegexOptions.CultureInvariant)]
    private static partial Regex Asking();

    /// "how many ounces in pound", "how many ounces in a pound" or "how many cups are in 2 gallons".
    [GeneratedRegex(@"^how many\s+(?<to>[a-z°""'/²0-9 ]+?)\s+(?:are\s+|is\s+)?in\s+(?:(?<amount>[-+]?\d+(?:[ .,]\d+)*)\s*|an?\s+|one\s+)?(?<from>[a-z°""'/²0-9 ]+?)\s*\??$",
        RegexOptions.CultureInvariant)]
    private static partial Regex HowMany();

    #endregion
}
