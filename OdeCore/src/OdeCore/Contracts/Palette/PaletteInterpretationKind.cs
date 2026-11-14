using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Each interpretation owns its resolution and source authorization.
public sealed class PaletteInterpretationKind {
    #region Static Variables

    public static readonly PaletteInterpretationKind Calculation = new("calculation", (input, lookup, preferences) =>
        preferences.Offers(PaletteSource.Calculator) ? input.Calculate(lookup.Text) : null);
    public static readonly PaletteInterpretationKind Conversion = new("conversion", (input, lookup, preferences) =>
        preferences.Offers(PaletteSource.Conversions)
            ? UnitConversion.Resolve(lookup.Text, input.Amount, input.FromUnit, input.ToUnit, input.Ingredient) : null);
    public static readonly PaletteInterpretationKind Clarification = new("clarification", (_, lookup, _) =>
        GenerativeAnswerLookup.NumericalRequest(lookup.Text)
            ? PaletteInterpretation.Clarification("Add the amount and units, or write the calculation.") : null);
    public static readonly PaletteInterpretationKind NoAnswer = new("noAnswer", (_, _, _) => null);
    public static IReadOnlyList<PaletteInterpretationKind> All { get; } = [Calculation, Conversion, Clarification, NoAnswer];

    #endregion

    #region Variables

    public string Name { get; }
    private readonly Func<PaletteInterpretation, PaletteGenerativeLookup, PalettePreferences, PaletteCard?> resolve;

    #endregion

    #region Constructors

    private PaletteInterpretationKind(string name,
        Func<PaletteInterpretation, PaletteGenerativeLookup, PalettePreferences, PaletteCard?> resolve) {
        Name = name;
        this.resolve = resolve;
    }

    #endregion

    #region Actions - Resolution

    public static PaletteInterpretationKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    internal PaletteCard? Resolve(PaletteInterpretation input, PaletteGenerativeLookup lookup, PalettePreferences preferences) =>
        resolve(input, lookup, preferences);

    #endregion
}
