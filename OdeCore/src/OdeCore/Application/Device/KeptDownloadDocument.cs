using System.Text.Json;
using System.Text.Json.Nodes;

using OdeCore.Contracts;

namespace OdeCore.Application;

/// An ended download as the device store keeps it beside its identity,
/// profile and start: its file's name and address, how it ended, and its
/// size, failure and message. A record it cannot read is left out.
internal static class KeptDownloadDocument {
    #region Static Variables

    private const string FilenameKey = "filename";
    private const string DestinationKey = "destination";
    private const string PhaseKey = "phase";
    private const string BytesKey = "bytes";
    private const string TotalBytesKey = "totalBytes";
    private const string FailureKey = "failure";
    private const string MessageKey = "message";

    #endregion

    #region Actions - Reading

    /// The record `document` holds for download `id` of profile `profileId`,
    /// started at `createdAt`; null when it does not read as an ended one.
    public static DownloadState? Read(Guid id, Guid profileId, DateTimeOffset createdAt, string? document) {
        if (document is null) return null;
        try {
            if (JsonNode.Parse(document, documentOptions: new() { MaxDepth = 4 }) is not JsonObject value
                || Text(value[FilenameKey]) is not { } filename || DownloadPhase.Named(Text(value[PhaseKey])) is not { } phase
                || phase.IsLive || phase.AwaitsDecision)
                return null;
            long bytes = Math.Max(0, Number(value[BytesKey]) ?? 0);
            long? total = Number(value[TotalBytesKey]) is { } kept && kept >= 0 ? kept : null;
            return new(id, profileId, createdAt, filename, Text(value[DestinationKey]), phase.IsComplete ? 1 : 0,
                new DownloadTelemetry(bytes, total, null, null, false), phase, DownloadFailure.Named(Text(value[FailureKey])),
                Text(value[MessageKey]), Risk: null, IsAcknowledged: true);
        } catch (JsonException) {
            return null;
        } catch (InvalidOperationException) {
            return null;
        }
    }

    #endregion

    #region Actions - Writing

    /// `download` as its one document.
    public static string Write(DownloadState download) {
        ArgumentNullException.ThrowIfNull(download);
        var value = new JsonObject {
            [FilenameKey] = download.Filename,
            [PhaseKey] = download.Phase.Name,
            [BytesKey] = download.Telemetry.BytesReceived
        };
        if (download.Destination is { } destination) value[DestinationKey] = destination;
        if (download.Telemetry.TotalBytes is { } total) value[TotalBytesKey] = total;
        if (download.Failure is { } failure) value[FailureKey] = failure.Name;
        if (download.Message is { } message) value[MessageKey] = message;
        return value.ToJsonString();
    }

    #endregion

    #region Actions - Support

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static long? Number(JsonNode? node) => node is JsonValue value && value.TryGetValue<long>(out var number) ? number : null;

    #endregion
}
