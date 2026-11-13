using OdeCore.Application;
using OdeCore.Domain;

namespace OdeCore.Contracts;

/// Forgets the person's choice for `Command`, which answers to its default
/// again. Nothing else loses its chord.
public sealed record ResetShortcut(ShortcutCommand Command) : ShortcutIntent {
    #region Actions - Device

    internal override void Apply(Device device, ShortcutTurn turn) =>
        device.ReviseShortcuts(turn, shortcuts => shortcuts.Resetting(Command));

    #endregion
}
