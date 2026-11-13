using OdeCore.Contracts;

namespace OdeCore.Domain;

/// What typed text asks the palette to work out itself, read once for each
/// query: arithmetic while the person offers the calculator, else, while
/// they offer conversions, an exact unit conversion, or the conversions a
/// partial one may be heading for and the time somewhere. The cards show
/// the first that answers, an outright answer keeps a written answer from
/// leading, and arithmetic is never sent away for suggestions.
internal sealed record LocalAnswer(Calculation? Calculation, UnitConversion? Conversion, IReadOnlyList<UnitConversion> Choices,
    ZoneClock? Clock) {
    #region Static Variables

    private static readonly LocalAnswer None = new(null, null, [], null);

    #endregion

    #region Variables

    /// The text asks for arithmetic, an exact conversion or a time, which a
    /// card answers outright; conversion choices only offer a guess.
    public bool AnswersOutright => Calculation is not null || Conversion is not null || Clock is not null;

    #endregion

    #region Actions - Reading

    /// What `text`, already trimmed, asks of the palette over `context`.
    public static LocalAnswer Of(PaletteContext context, string text) {
        if (Arithmetic(context, text) is { } calculation) return new(calculation, null, [], null);
        if (!context.Preferences.Offers(PaletteSource.Conversions)) return None;
        if (UnitConversion.Of(text) is { } conversion) return new(null, conversion, [], null);
        return new(null, null, UnitConversion.Choices(text), ZoneClock.Of(text, context.Now, context.Zone));
    }

    /// The arithmetic `text`, already trimmed, asks for while the person
    /// offers the calculator, or null.
    public static Calculation? Arithmetic(PaletteContext context, string text) =>
        context.Preferences.Offers(PaletteSource.Calculator) ? Calculation.Of(text) : null;

    #endregion
}
