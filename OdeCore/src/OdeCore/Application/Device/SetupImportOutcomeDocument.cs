using System.Text.Json;
using System.Text.Json.Nodes;

using OdeCore.Contracts;

namespace OdeCore.Application;

/// The private device-store representation, separate from the generated wire.
internal static class SetupImportOutcomeDocument {
    #region Actions - Reading

    public static SetupImportOutcome? Read(string? document) {
        try {
            if (document is null || JsonNode.Parse(document) is not JsonObject value || Heading(value) is not { } heading) return null;
            var omissions = value["omissions"]?.AsArray().Select(item => item!.GetValue<string>()).ToArray() ?? [];
            var extensions = value["extensions"]?.AsArray().Select(ReadExtension).ToArray() ?? [];
            if (extensions.Any(item => !Enum.IsDefined(item.Status))) return null;
            return new(heading.Id, heading.Title, heading.Status, Count(value, "tabs"), Count(value, "spaces"), Count(value, "passwords"),
                Count(value, "passwordsSkipped"), omissions, Count(value, "cookies"), Count(value, "cookiesExpired"),
                Count(value, "cookiesDropped"), Count(value, "signInSpacesSkipped"), extensions);
        } catch (Exception error) when (error is JsonException or InvalidOperationException or FormatException or NullReferenceException) {
            return null;
        }
    }

    /// The receipt's id, source title and status, or null when one is missing
    /// or the status is one this build cannot name.
    private static (Guid Id, string Title, SetupImportOutcomeStatus Status)? Heading(JsonObject value) {
        if (!Guid.TryParse(value["id"]?.GetValue<string>(), out var id) || value["title"]?.GetValue<string>() is not { } title) return null;
        var status = (SetupImportOutcomeStatus)(value["status"]?.GetValue<int>() ?? -1);
        return Enum.IsDefined(status) ? (id, title, status) : null;
    }

    /// One extension's entry; a missing status reads as one no build names.
    private static SetupImportExtensionOutcome ReadExtension(JsonNode? item) {
        var extension = item!.AsObject();
        return new(extension["id"]!.GetValue<string>(), extension["name"]!.GetValue<string>(),
            Guid.Parse(extension["space"]!.GetValue<string>()), (SetupImportExtensionStatus)(extension["status"]?.GetValue<int>() ?? -1));
    }

    private static int Count(JsonObject value, string key) => Math.Max(0, value[key]?.GetValue<int>() ?? 0);

    #endregion

    #region Actions - Writing

    public static string Write(SetupImportOutcome outcome, string? previousDocument = null) {
        // Keep unknown fields when a newer build has already extended a receipt.
        var value = previousDocument is null ? new JsonObject() : JsonNode.Parse(previousDocument)?.AsObject() ?? new JsonObject();
        var previousExtensions = value["extensions"]?.AsArray().ToArray() ?? [];
        value["id"] = outcome.Id.ToString("D");
        value["title"] = outcome.SourceTitle;
        value["status"] = (int)outcome.Status;
        value["tabs"] = outcome.TabCount;
        value["spaces"] = outcome.SpaceCount;
        value["passwords"] = outcome.PasswordCount;
        value["passwordsSkipped"] = outcome.PasswordSkippedCount;
        value["cookies"] = outcome.CookieCount;
        value["cookiesExpired"] = outcome.ExpiredCookieCount;
        value["cookiesDropped"] = outcome.DroppedCookieCount;
        value["signInSpacesSkipped"] = outcome.SignInSpacesSkipped;
        value["omissions"] = new JsonArray(outcome.Omissions.Select(item => (JsonNode?)JsonValue.Create(item)).ToArray());
        value["extensions"] = new JsonArray(outcome.Extensions.Select(item => (JsonNode?)WriteExtension(item, previousExtensions)).ToArray());
        return value.ToJsonString();
    }

    /// `item`'s entry, written over a copy of the entry an earlier write kept
    /// for the same extension and Space, so fields a newer build added stay.
    private static JsonObject WriteExtension(SetupImportExtensionOutcome item, IReadOnlyList<JsonNode?> previousExtensions) {
        var kept = previousExtensions.FirstOrDefault(node => node?["id"]?.GetValue<string>() == item.ExtensionId
            && Guid.TryParse(node?["space"]?.GetValue<string>(), out var spaceId) && spaceId == item.SpaceId);
        var extension = kept?.DeepClone().AsObject() ?? new JsonObject();
        extension["id"] = item.ExtensionId;
        extension["name"] = item.Name;
        extension["space"] = item.SpaceId.ToString("D");
        extension["status"] = (int)item.Status;
        return extension;
    }

    #endregion
}
