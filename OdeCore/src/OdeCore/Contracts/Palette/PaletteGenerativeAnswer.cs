namespace OdeCore.Contracts;

/// Typed text only, selected by the core for a private on-device preview.
/// Never contains page, tab, history or credential context.
public sealed record PaletteGenerativeLookup(string Text);

/// Transient service output, never persisted, learned or synchronized.
public sealed record PaletteGenerativeResult(PaletteGenerativeLookup Lookup, string? Text, PaletteGenerativeStatus Status);

public sealed class PaletteGenerativeStatus {
    #region Static Variables

    public static readonly PaletteGenerativeStatus Waiting = new("waiting", "Thinking on device…");
    public static readonly PaletteGenerativeStatus Answered = new("answered", "");
    public static readonly PaletteGenerativeStatus DeviceNotEligible = new("deviceNotEligible", "This device can’t run Apple’s on-device model.");
    public static readonly PaletteGenerativeStatus IntelligenceDisabled = new("intelligenceDisabled", "Turn on Apple Intelligence in System Settings to use Ode’s on-device answers.");
    public static readonly PaletteGenerativeStatus ModelNotReady = new("modelNotReady", "Apple’s on-device model isn’t ready. Try again later.");
    public static readonly PaletteGenerativeStatus Unavailable = new("unavailable", "Apple’s on-device model isn’t available.");
    public static readonly PaletteGenerativeStatus Busy = new("busy", "Apple’s on-device model is busy. Try again.");
    public static readonly PaletteGenerativeStatus Refused = new("refused", "Apple’s on-device model couldn’t answer this request.");
    public static readonly PaletteGenerativeStatus Failed = new("failed", "Ode couldn’t finish. Try again.");
    public static IReadOnlyList<PaletteGenerativeStatus> All { get; } =
        [Waiting, Answered, DeviceNotEligible, IntelligenceDisabled, ModelNotReady, Unavailable, Busy, Refused, Failed];

    #endregion

    #region Variables

    public string Name { get; }
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private PaletteGenerativeStatus(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteGenerativeStatus? Named(string? name) => All.FirstOrDefault(status => status.Name == name);

    #endregion
}
