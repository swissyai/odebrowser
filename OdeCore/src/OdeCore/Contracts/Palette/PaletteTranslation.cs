namespace OdeCore.Contracts;

/// The phrase and named target parsed by the core. A missing source must be
/// recognized on device, never silently replaced with English.
public sealed record PaletteTranslationLookup(string Text, string? SourceLanguage, string TargetLanguage);

/// Transient Apple service output. It is never a preference, history entry,
/// learned palette choice or sync record.
public sealed record PaletteTranslationResult(PaletteTranslationLookup Lookup, string? SourceLanguage, string? Text,
    PaletteTranslationStatus Status);

public sealed class PaletteTranslationStatus {
    #region Static Variables

    public static readonly PaletteTranslationStatus Waiting = new("waiting", "Translating on device…");
    public static readonly PaletteTranslationStatus Translated = new("translated", "");
    public static readonly PaletteTranslationStatus NotInstalled = new("notInstalled",
        "Download this language pair in Apple’s translation language settings, then retry.");
    public static readonly PaletteTranslationStatus Unsupported = new("unsupported", "Apple Translation doesn’t support this language pair.");
    public static readonly PaletteTranslationStatus Unidentified = new("unidentified",
        "Couldn’t identify the source language. Try “translate phrase from language to language”.");
    public static readonly PaletteTranslationStatus SameLanguage = new("sameLanguage", "This phrase is already in the target language.");
    public static readonly PaletteTranslationStatus Failed = new("failed", "Translation couldn’t finish. Try again.");
    public static IReadOnlyList<PaletteTranslationStatus> All { get; } =
        [Waiting, Translated, NotInstalled, Unsupported, Unidentified, SameLanguage, Failed];

    #endregion

    #region Variables

    public string Name { get; }
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private PaletteTranslationStatus(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteTranslationStatus? Named(string? name) => All.FirstOrDefault(status => status.Name == name);

    #endregion
}
