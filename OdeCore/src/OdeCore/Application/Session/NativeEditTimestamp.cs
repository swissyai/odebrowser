using OdeCore.Domain;

namespace OdeCore.Application;

internal static class NativeEditTimestamp {
    #region Actions - Session

    internal static double Encode(DateTimeOffset value) =>
        BrowserEditTimestamp.NormalizeUnixSeconds((value - DateTimeOffset.UnixEpoch).TotalSeconds)
            - StoredSessionCodec.ReferenceEpochUnixSeconds;

    #endregion
}
