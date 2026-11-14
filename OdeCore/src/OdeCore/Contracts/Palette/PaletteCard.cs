namespace OdeCore.Contracts;

/// A short answer the palette shows below the search for what was typed,
/// worked out on the device or, where the person allows it, fetched: a unit
/// conversion, the time somewhere, a definition from the Mac's dictionary,
/// a real on-device translation or an encyclopedia summary. `Title` and `Subtitle` lead the card and `Body`
/// follows. Return copies `Value`, looks `Term` up in the dictionary or opens
/// `Address`, as its kind says. `Clock` holds the moment and zones a time
/// card tells, which the platform writes in the person's own format.
/// `Image` is a freely licensed picture with its credit, and `Credit`, with
/// `CreditAddress`, `License` and `LicenseAddress`, says where the text
/// comes from and under what licence.
public sealed record PaletteCard(PaletteCardKind Kind, string Title, string Subtitle, string? Body, string? Value, string? Address,
    string? Term, PaletteCardClock? Clock, PaletteCardImage? Image, string? Credit, string? CreditAddress, string? License,
    string? LicenseAddress);

/// The moment a time card tells, the IANA zone it tells it in and that
/// zone's place, the zone and place a person gave a time of day in, or null
/// for the time now, and how far ahead or behind the zone is, as words.
public sealed record PaletteCardClock(DateTimeOffset Instant, string Zone, string Place, string? FromZone, string? FromPlace,
    string Difference);

/// A picture a card shows, at `Address`, with `Credit` naming its author and
/// licence and `CreditAddress` the page that holds both.
public sealed record PaletteCardImage(string Address, string Credit, string CreditAddress);

/// Where the platform looks a topic up for an encyclopedia card: `Topic`,
/// the text without "who is" or "what is"; `SearchAddress`, the title search
/// whose first title must be the topic; `SummaryTemplate`, the article's
/// summary for `%s`, the found page's key; and `ImageInfoTemplate`, the
/// author and licence of a Commons picture for `%s`, its file name.
public sealed record PaletteWebLookup(string Topic, string SearchAddress, string SummaryTemplate, string ImageInfoTemplate);

/// What the platform fetched for a `PaletteWebLookup`: the article's title,
/// its kind, as `standard` for an ordinary article, its short description,
/// the start of its text, its page, and its picture's address with the
/// author and licence Commons gives for it, each null where there is none.
public sealed record PaletteWebSummary(string Title, string Type, string? Description, string Extract, string Page,
    string? Thumbnail, string? ImageArtist, string? ImageLicense);

/// What the Mac's dictionary says for `Term`, which the palette asked the
/// platform to look up; a null `Text` means the Mac has no dictionary yet, as
/// before it finishes downloading one.
public sealed record PaletteDefinition(string Term, string? Text);

/// What a card is, the word that names it, the symbol it wears, and what
/// Return does with it: copy its value, look its term up in the dictionary,
/// or open its address. A kind travels as its index in `All`, so `All` is
/// append-only.
public sealed class PaletteCardKind {
    #region Static Variables

    public static readonly PaletteCardKind Conversion = new(name: "conversion", label: "Conversion", symbol: "arrow.left.arrow.right",
        copiesValue: true, looksUpTerm: false);
    public static readonly PaletteCardKind Time = new(name: "time", label: "Time", symbol: "clock", copiesValue: true, looksUpTerm: false);
    public static readonly PaletteCardKind Definition = new(name: "definition", label: "Dictionary", symbol: "character.book.closed",
        copiesValue: false, looksUpTerm: true);
    public static readonly PaletteCardKind Encyclopedia = new(name: "encyclopedia", label: "Wikipedia", symbol: "book",
        copiesValue: false, looksUpTerm: false);

    public static readonly PaletteCardKind Calculation = new(name: "calculation", label: "Calculator", symbol: "equal",
        copiesValue: true, looksUpTerm: false);

    public static readonly PaletteCardKind Translation = new(name: "translation", label: "Translation", symbol: "translate",
        copiesValue: true, looksUpTerm: false);

    public static readonly PaletteCardKind GenerativeAnswer = new(name: "generativeAnswer", label: "Ode", symbol: "sparkles",
        copiesValue: true, looksUpTerm: false);

    /// A local question with no copy, dictionary or navigation action.
    public static readonly PaletteCardKind Clarification = new(name: "clarification", label: "Conversion", symbol: "questionmark.circle",
        copiesValue: false, looksUpTerm: false);

    public static IReadOnlyList<PaletteCardKind> All { get; } = [Conversion, Time, Definition, Encyclopedia, Calculation, Translation, GenerativeAnswer, Clarification];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the card says it is.
    [Localized]
    public string Label { get; }

    /// The SF Symbol the card wears where it shows no picture.
    public string Symbol { get; }

    /// Return copies the card's value.
    public bool CopiesValue { get; }

    /// Return looks the card's term up in the Mac's dictionary.
    public bool LooksUpTerm { get; }

    #endregion

    #region Constructors

    private PaletteCardKind(string name, string label, string symbol, bool copiesValue, bool looksUpTerm) {
        Name = name;
        Label = label;
        Symbol = symbol;
        CopiesValue = copiesValue;
        LooksUpTerm = looksUpTerm;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteCardKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
