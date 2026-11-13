using OdeCore.Application;

namespace OdeCore.Contracts;

/// This device's agent preferences.
public sealed record GetAgentPreferences : Query<AgentPreferences> {
    #region Actions - Answering

    internal override AgentPreferences Answer(OdeApp app) => app.Device.Agents;

    #endregion
}
