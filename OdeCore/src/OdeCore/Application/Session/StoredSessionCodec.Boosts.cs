using System.Text.Json;
using System.Text.Json.Nodes;

using OdeCore.Contracts;

namespace OdeCore.Application;

internal static partial class StoredSessionCodec {
    #region Actions - Boosts

    /// A Space's Boosts, as the Boost rules keep them: anything but a list
    /// reads as none, an entry that is not an object or names no site is left
    /// out, as is a later entry for a site already read, and a member that is
    /// missing or of another type takes the value that changes nothing. Null
    /// when none is kept.
    internal static SpaceBoosts? DecodeBoosts(JsonNode? node) =>
        SpaceBoosts.Kept((node as JsonArray ?? []).Select(item => item is JsonObject value ? DecodeBoost(value) : null));

    private static SiteBoost? DecodeBoost(JsonObject value) => TolerantText(value[Key.Site]) is { } site
        ? new(site, TolerantFlag(value[Key.IsEnabled]) ?? true, TolerantFlag(value[Key.IsDark]) ?? false,
            TolerantNumber(value[Key.TintHue]) ?? 0, TolerantNumber(value[Key.TintStrength]) ?? 0,
            TolerantNumber(value[Key.Brightness]) ?? 1, TolerantNumber(value[Key.Contrast]) ?? 1,
            BoostFont.Named(TolerantText(value[Key.Font])),
            [.. (value[Key.HiddenSelectors] as JsonArray ?? []).Select(TolerantText).OfType<string>()],
            TolerantText(value[Key.CustomCss]) ?? "")
        : null;

    /// A Space's Boosts, each with every member but a font it has none of.
    internal static JsonArray Encode(SpaceBoosts boosts) => EncodeAll(boosts.Sites, boost => {
        var value = new JsonObject {
            [Key.Site] = boost.Site,
            [Key.IsEnabled] = boost.IsEnabled,
            [Key.IsDark] = boost.IsDark,
            [Key.TintHue] = boost.TintHue,
            [Key.TintStrength] = boost.TintStrength,
            [Key.Brightness] = boost.Brightness,
            [Key.Contrast] = boost.Contrast,
            [Key.HiddenSelectors] = new JsonArray([.. boost.HiddenSelectors.Select(selector => (JsonNode?)selector)]),
            [Key.CustomCss] = boost.CustomCss
        };
        Put(value, Key.Font, boost.Font?.Name);
        return value;
    });

    /// A number that reads as absent when it holds anything but a finite number.
    private static double? TolerantNumber(JsonNode? node) =>
        node is JsonValue value && value.GetValueKind() == JsonValueKind.Number && value.GetValue<double>() is var number
            && double.IsFinite(number) ? number : null;

    #endregion
}
