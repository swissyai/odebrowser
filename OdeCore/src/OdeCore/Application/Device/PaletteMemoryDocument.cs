using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

using OdeCore.Domain;

namespace OdeCore.Application;

/// A Space's palette memory as the device store keeps it: one JSON document
/// with when it began, each place's decay day, last typed time and typed
/// uses, and each pick. A part it cannot read is left out, and a place
/// written before typed uses were kept reads as typed no times; a document
/// it cannot read at all reads as no memory.
internal static class PaletteMemoryDocument {
    #region Static Variables

    private const string SinceKey = "since";
    private const string PlacesKey = "places";
    private const string PlaceKey = "place";
    private const string DecayDayKey = "decayDay";
    private const string TypedAtKey = "typedAt";
    private const string TypedUsesKey = "typedUses";
    private const string ChoicesKey = "choices";
    private const string TextKey = "text";
    private const string KindKey = "kind";
    private const string ValueKey = "value";
    private const string UsesKey = "uses";
    private const string UsedAtKey = "usedAt";

    #endregion

    #region Actions - Reading

    /// The memory `document` holds, or null when it does not read.
    public static PaletteMemory? Read(string? document) {
        if (document is null) return null;
        try {
            if (JsonNode.Parse(document, documentOptions: new() { MaxDepth = 8 }) is not JsonObject value
                || Date(value[SinceKey]) is not { } since) return null;
            var places = ImmutableDictionary.CreateBuilder<string, PlaceUse>(StringComparer.Ordinal);
            foreach (var place in Entries(value[PlacesKey]))
                if (ReadPlace(place) is { } read) places[read.Key] = read.Use;
            var choices = Entries(value[ChoicesKey]).Select(ReadChoice).OfType<PaletteChoice>().ToImmutableList();
            return new(since, places.ToImmutable(), choices);
        } catch (JsonException) {
            return null;
        } catch (InvalidOperationException) {
            return null;
        }
    }

    /// The objects `node` lists, or none when it is no list.
    private static IEnumerable<JsonObject> Entries(JsonNode? node) => (node as JsonArray ?? []).OfType<JsonObject>();

    /// A remembered place and its use, or null for one missing its place or
    /// decay day; a negative count of typed uses reads as none.
    private static (string Key, PlaceUse Use)? ReadPlace(JsonObject place) {
        if (Text(place[PlaceKey]) is not { } key || Number(place[DecayDayKey]) is not { } decayDay) return null;
        return (key, new(decayDay, Date(place[TypedAtKey]), (int)Math.Max(0, Number(place[TypedUsesKey]) ?? 0)));
    }

    /// A learned choice, or null for one missing a field or naming a kind of
    /// destination this build cannot.
    private static PaletteChoice? ReadChoice(JsonObject choice) {
        if (Text(choice[TextKey]) is not { } text || PaletteDestinationKind.Named(Text(choice[KindKey])) is not { } kind
            || Text(choice[ValueKey]) is not { } target || Number(choice[UsesKey]) is not { } uses || Date(choice[UsedAtKey]) is not { } usedAt)
            return null;
        return new(text, PaletteDestination.Named(kind, target), uses, usedAt);
    }

    #endregion

    #region Actions - Writing

    /// `memory` as its one document.
    public static string Write(PaletteMemory memory) {
        ArgumentNullException.ThrowIfNull(memory);
        var value = new JsonObject {
            [SinceKey] = Spelled(memory.Since),
            [PlacesKey] = new JsonArray([.. memory.Places.OrderBy(place => place.Key, StringComparer.Ordinal).Select(place => (JsonNode)new JsonObject {
                [PlaceKey] = place.Key,
                [DecayDayKey] = place.Value.DecayDay,
                [TypedAtKey] = place.Value.TypedAt is { } typed ? Spelled(typed) : null,
                [TypedUsesKey] = place.Value.TypedUses > 0 ? place.Value.TypedUses : null
            })]),
            [ChoicesKey] = new JsonArray([.. memory.Choices.Select(choice => (JsonNode)new JsonObject {
                [TextKey] = choice.Text,
                [KindKey] = choice.Destination.Kind.Name,
                [ValueKey] = choice.Destination.Value,
                [UsesKey] = choice.Uses,
                [UsedAtKey] = Spelled(choice.LastUsedAt)
            })])
        };
        return value.ToJsonString();
    }

    #endregion

    #region Actions - Support

    private static string Spelled(DateTimeOffset date) => date.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);

    private static DateTimeOffset? Date(JsonNode? node) =>
        Text(node) is { } text && DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var date)
            ? date : null;

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static double? Number(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue<double>(out var number) && double.IsFinite(number) ? number : null;

    #endregion
}
