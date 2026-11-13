namespace OdeCore.Contracts;

#region Queries

/// Branding as a Space keeps it once the core's range rules apply.
public sealed record NormalizedBranding(SpaceBranding Branding);

#endregion

#region Models - Emblems

/// <summary>
/// A emblem's custom figure: a heraldic <see cref="Symbol"/>, or <see cref="Text"/> naming
/// a system symbol, an emoji or the letters of a monogram in its <see cref="Style"/>.
/// </summary>
public sealed record EmblemCharge(EmblemChargeKind Kind, EmblemSymbol? Symbol = null, string? Text = null,
    EmblemMonogramStyle? Style = null);

#endregion

