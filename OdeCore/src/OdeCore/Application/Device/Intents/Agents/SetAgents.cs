using OdeCore.Application;

namespace OdeCore.Contracts;

/// Lets agents use Ode, or stops them; turning agents off disconnects every
/// agent. The Spaces and agents the person chose are kept either way.
/// Turning agents on gives them a Space of their own in the person's session,
/// named Agents, when they have none; turning them off keeps it.
public sealed record SetAgents(bool IsOn) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var made = IsOn ? device.MakeAgentsSpace(turn) : null;
        device.ReviseAgents(turn.Changes, preferences =>
            (made is { } spaceId ? preferences.Giving(spaceId) : preferences) with { IsOn = IsOn });
    }

    #endregion
}
