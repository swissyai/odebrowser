using OdeCore.Contracts;

namespace OdeCore.Domain;

/// The short answers the palette shows below the search: arithmetic, a
/// unit conversion or the time somewhere, worked out here, else a definition
/// the platform looked up in the device's dictionary, else, where the person
/// turned web answers on, an encyclopedia summary the platform fetched. A
/// card never leads, so a late one never moves the row Return runs, and a
/// local card needs no dictionary or web-answer lookup.
public sealed partial class Palette {
    #region Actions - Cards

    /// The card rows for typed text: what `local` works out, arithmetic,
    /// exact or predictive unit conversions, or a time, first, then the
    /// definition brought for the word the palette asked about, while nothing
    /// local leads.
    private IReadOnlyList<PaletteRow> Cards(LocalAnswer local, PaletteQuery query, PaletteSuggestions question, PaletteRow? intent,
        PaletteCandidate? lead, PaletteTranslationLookup? translation, PaletteGenerativeLookup? generative) {
        if (translation is not null) return [Row(TranslationLookup.Card(translation, question.Translation))];
        if (local.Calculation is { } calculation)
            return [Row(new(PaletteCardKind.Calculation, calculation.Answer, $"{calculation.Expression} =", Body: null, calculation.Answer,
                Address: null, Term: null, Clock: null, Image: null, Credit: null, CreditAddress: null, License: null,
                LicenseAddress: null))];
        if (local.Conversion is { } conversion) return [ConversionRow(conversion)];
        if (local.NeedsIngredient) {
            var enriched = generative is null ? null : GenerativeAnswerLookup.Card(generative, question.Generative, Preferences, query.Text);
            return [Row(enriched ?? UnitConversion.IngredientClarification(query.Text))];
        }
        if (local.Choices.Count > 0) return [.. local.Choices.Select(ConversionRow)];
        if (local.Clock is { } clock)
            return [Row(new(PaletteCardKind.Time, clock.Place, clock.Difference, Body: null, Value: null, Address: null, Term: null,
                new(clock.Instant, clock.Zone, clock.Place, clock.FromZone, clock.FromPlace, clock.Difference), Image: null,
                Credit: null, CreditAddress: null, License: null, LicenseAddress: null))];
        if (DefinitionCard(query, question, intent, lead) is { } defined) return [Row(defined)];
        if (generative is not null)
            return GenerativeAnswerLookup.Card(generative, question.Generative, Preferences, query.Text) is { } generated
                ? [Row(generated)] : [];
        if (WebCard(query, question, intent, lead) is { } summarized) return [Row(summarized)];
        return [];
    }

    private PaletteCard? DefinitionCard(PaletteQuery query, PaletteSuggestions question, PaletteRow? intent, PaletteCandidate? lead) =>
        question.Definition is { } definition && DefinitionTerm(query, intent, lead) == definition.Term
            ? DictionaryLookup.Card(definition, DictionaryLookup.AsksOutright(query.Text)) : null;

    private PaletteCard? WebCard(PaletteQuery query, PaletteSuggestions question, PaletteRow? intent, PaletteCandidate? lead) =>
        question.WebSummary is { } summary && WebLookup(query, intent, lead) is { } lookup
            ? WebAnswer.Card(summary, lookup.Topic) : null;

    /// An optional translation never replaces the person's Return search,
    /// even when an existing how-to answer also matches its words.
    private PaletteCandidate? LeadingRow(PaletteTranslationLookup? translation, PaletteLeading leading) {
        if (translation is not null) return null;
        if (Preferences.Offers(PaletteSource.AskOde) && Preferences.Offers(PaletteSource.Answers)
            && GenerativeAnswerLookup.IsExplicit(leading.Query.Text) && !leading.Local.AnswersOutright
            && AnswerCatalog.Shipped.Index.Lead(GenerativeAnswerLookup.Input(leading.Query.Text)) is { } help)
            return new(AnswerFinder.Row(help, PaletteReason.Answers), PaletteSource.Answers, int.MaxValue, Place: null, MayLead: true);
        return PaletteLeadRule.First(context, leading);
    }

    private static PaletteTranslationLookup? TranslationFor(PaletteQuery query, PaletteRow? intent) =>
        intent?.Kind != PaletteRowKind.OpenAddress && !NamesScheme(query.Text) ? TranslationLookup.Of(query.Text) : null;

    /// The core alone authorizes the native local-model boundary. Existing
    /// numeric, translation, dictionary and curated help answers win first.
    private PaletteGenerativeLookup? GenerativeFor(PaletteQuery query, PaletteRow? intent, PaletteCandidate? lead,
        LocalAnswer local, PaletteTranslationLookup? translation) {
        if (!Preferences.Offers(PaletteSource.AskOde) || context.Space is null || lead is not null || translation is not null
            || TranslationLookup.IsExplicit(query.Text)
            || local.AnswersOutright && !local.NeedsIngredient || local.Choices.Count > 0 || UnitConversion.IsBareMeasurement(query.Text)
            || intent?.Kind == PaletteRowKind.OpenAddress
            || context.Catalog.NamedBy(query.Text) is not null
            || DefinitionTerm(query, intent, lead) is not null
            || AnswerCatalog.Shipped.Index.Lead(GenerativeAnswerLookup.Input(query.Text)) is not null) return null;
        return GenerativeAnswerLookup.Of(query.Text);
    }

    private bool KeepsQueryPrivate(string text) =>
        TranslationLookup.IsExplicit(text) || GenerativeAnswerLookup.KeepsPrivate(text, Preferences);

    private PaletteAnswer WithLookups(PaletteAnswer answer, PaletteQuery query, PaletteRow? intent, PaletteCandidate? lead,
        LocalAnswer local, bool hasCard, PaletteTranslationLookup? translation, PaletteGenerativeLookup? generative) {
        bool keepsPrivate = KeepsQueryPrivate(query.Text);
        return answer with {
            SuggestionAddress = keepsPrivate ? null : SuggestionAddress(query.Text, intent, lead, local, translation),
            DefinitionTerm = hasCard ? null : DefinitionTerm(query, intent, lead),
            WebLookup = keepsPrivate || hasCard ? null : WebLookup(query, intent, lead),
            TranslationLookup = translation,
            GenerativeLookup = generative,
            KeepsQueryPrivate = keepsPrivate,
        };
    }

    private static PaletteRow ConversionRow(UnitConversion conversion) =>
        Row(new(PaletteCardKind.Conversion, conversion.Answered, $"{conversion.Asked} =", Body: null, conversion.Answer,
            Address: null, Term: null, Clock: null, Image: null, Credit: null, CreditAddress: null, License: null, LicenseAddress: null));

    /// Where the platform may look `query` up for an encyclopedia card, or
    /// null: only while the person turned web answers on, outside a private
    /// window, for a Space the palette may read, while nothing local leads,
    /// and for a topic that is no address, secret or search provider's name.
    private PaletteWebLookup? WebLookup(PaletteQuery query, PaletteRow? intent, PaletteCandidate? lead) {
        if (!Preferences.Offers(PaletteSource.WebAnswers) || context.IsPrivate || context.Space is null || lead is not null
            || intent?.Kind == PaletteRowKind.OpenAddress || NamesScheme(query.Text) || SecretText.Looks(query.Text)
            || query.Text.Length > MaximumSuggestionLength || context.Catalog.NamedBy(query.Text) is not null
            || WebAnswer.Topic(query.Text) is not { } topic)
            return null;
        return WebAnswer.Lookup(topic, context.Catalog.Resolving(BuiltInSearchProvider.Wikipedia));
    }

    /// The word the platform may look up in the device's dictionary for
    /// `query`, or null: only while the person offers definitions, nothing
    /// local leads, the text is no address, secret or provider's name, and
    /// it asks about a word.
    private string? DefinitionTerm(PaletteQuery query, PaletteRow? intent, PaletteCandidate? lead) {
        if (!Preferences.Offers(PaletteSource.Dictionary) || lead is not null && lead.Source != PaletteSource.Answers
            || intent?.Kind == PaletteRowKind.OpenAddress || SecretText.Looks(query.Text) || context.Catalog.NamedBy(query.Text) is not null)
            return null;
        return DictionaryLookup.Term(query.Text);
    }

    private static PaletteRow Row(PaletteCard card) =>
        PaletteRow.Of(PaletteRowKind.Card, card.Title, card.Subtitle, symbol: card.Kind.Symbol, address: card.Address, card: card);

    #endregion
}
