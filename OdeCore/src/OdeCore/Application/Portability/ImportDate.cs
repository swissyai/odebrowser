namespace OdeCore.Application;

/// The times imports and Ode browser-data files carry. Floating-point times
/// follow the Apple platforms' seconds since 2001; integer browser timestamps
/// retain their exact ticks.
internal static class ImportDate {
    #region Static Variables

    /// Seconds from 1970 to 2001.
    private const double ReferenceOffset = StoredSessionCodec.ReferenceEpochUnixSeconds;

    /// Seconds from 1601, where Windows and Chromium count from, to 1970.
    private const double WindowsOffset = 11_644_473_600;
    private static readonly DateTimeOffset WindowsEpoch = new(1601, 1, 1, 0, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Reading

    /// A time given in seconds since 1970, or null when it is not a finite
    /// time.
    public static DateTimeOffset? FromUnixSeconds(double seconds) {
        double reference = seconds - ReferenceOffset;
        return double.IsFinite(reference) ? StoredSessionCodec.Date(reference) : null;
    }

    /// A time given in milliseconds since 1970.
    public static DateTimeOffset? FromUnixMilliseconds(double milliseconds) => FromUnixSeconds(milliseconds / 1_000);

    /// A time given in integer microseconds since 1970, without rounding
    /// through floating-point seconds before persistence.
    public static DateTimeOffset? FromUnixMicroseconds(long microseconds) {
        if (microseconds < -DateTimeOffset.UnixEpoch.Ticks / TimeSpan.TicksPerMicrosecond) return DateTimeOffset.MinValue;
        if (microseconds > (DateTimeOffset.MaxValue.Ticks - DateTimeOffset.UnixEpoch.Ticks) / TimeSpan.TicksPerMicrosecond)
            return DateTimeOffset.MaxValue;
        return DateTimeOffset.UnixEpoch.AddTicks(microseconds * TimeSpan.TicksPerMicrosecond);
    }

    /// Integer browser timestamps retain their exact ticks. Converting large
    /// Windows timestamps through double seconds can move whole milliseconds
    /// backwards; persistence then merges genuinely distinct visit times.
    public static DateTimeOffset? FromWindowsMicroseconds(long microseconds) {
        if (microseconds < -WindowsEpoch.Ticks / TimeSpan.TicksPerMicrosecond) return DateTimeOffset.MinValue;
        if (microseconds > (DateTimeOffset.MaxValue.Ticks - WindowsEpoch.Ticks) / TimeSpan.TicksPerMicrosecond)
            return DateTimeOffset.MaxValue;
        return WindowsEpoch.AddTicks(microseconds * TimeSpan.TicksPerMicrosecond);
    }

    /// A time given in microseconds since 1601, when only a floating-point
    /// timestamp is available.
    public static DateTimeOffset? FromWindowsMicroseconds(double microseconds) =>
        FromUnixSeconds(microseconds / 1_000_000 - WindowsOffset);

    /// A time given in seconds since 1970 or, when it is too large to be
    /// seconds, in milliseconds.
    public static DateTimeOffset? FromUnixSecondsOrMilliseconds(double value) =>
        FromUnixSeconds(value > 10_000_000_000 ? value / 1_000 : value);

    /// A time given in whichever unit its size suggests: microseconds since
    /// 1601, microseconds, milliseconds or seconds since 1970.
    public static DateTimeOffset? FromAnyUnit(double value) => value switch {
        > 10_000_000_000_000_000 => FromWindowsMicroseconds(value),
        > 10_000_000_000_000 => FromUnixSeconds(value / 1_000_000),
        > 10_000_000_000 => FromUnixMilliseconds(value),
        _ => FromUnixSeconds(value)
    };

    /// A time given in seconds or milliseconds since 1970 or, when it is too
    /// small to be a time since 2001 counted that way, in seconds since 2001,
    /// as apps on Apple's platforms keep them.
    public static DateTimeOffset? FromUnixOrReferenceSeconds(double value) =>
        value is > 0 and < ReferenceOffset ? FromReferenceSeconds(value) : FromUnixSecondsOrMilliseconds(value);

    /// A time given in seconds since 2001, as property lists keep them.
    public static DateTimeOffset? FromReferenceSeconds(double seconds) =>
        double.IsFinite(seconds) ? StoredSessionCodec.Date(seconds) : null;

    #endregion

    #region Actions - Writing

    /// Seconds since 1970.
    public static double UnixSeconds(DateTimeOffset date) => StoredSessionCodec.Seconds(date) + ReferenceOffset;

    /// Milliseconds since 1970, as Ode browser-data files keep times.
    public static double UnixMilliseconds(DateTimeOffset date) => UnixSeconds(date) * 1_000;

    #endregion
}
