namespace OdeCore.Contracts;

/// A started receipt is intentionally uncertain after interruption: the person
/// must check their Spaces before retrying, because platform side effects may
/// already have happened. Receipts contain no credentials, cookie values or paths.
// Persisted numeric values are append-only.
public enum SetupImportOutcomeStatus {
    Started,
    Imported,
    Failed,
    Cancelled
}

public enum SetupImportExtensionStatus {
    Pending,
    Installed,
    Failed,
    Removed
}

/// One approved extension destination. Installation is confirmed from the
/// engine's inventory, not from queueing or completion of a download job.
public sealed record SetupImportExtensionOutcome(string ExtensionId, string Name, Guid SpaceId, SetupImportExtensionStatus Status);

/// Device-local evidence of one import attempt. Omissions are person-facing
/// descriptions; passwords and cookies themselves never enter this record.
public sealed record SetupImportOutcome(Guid Id, string SourceTitle, SetupImportOutcomeStatus Status,
    int TabCount, int SpaceCount, int PasswordCount, int PasswordSkippedCount, IReadOnlyList<string> Omissions,
    int CookieCount, int ExpiredCookieCount, int DroppedCookieCount, int SignInSpacesSkipped,
    IReadOnlyList<SetupImportExtensionOutcome> Extensions);

public sealed record SetupImportOutcomes(IReadOnlyList<SetupImportOutcome> Items);
