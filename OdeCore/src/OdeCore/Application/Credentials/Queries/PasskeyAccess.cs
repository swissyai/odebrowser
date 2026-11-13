using OdeCore.Application;

namespace OdeCore.Contracts;

/// Whether websites in Ode can use the system's passkey providers, from the
/// platform's build, device and authorization facts.
public sealed record PasskeyAccess(bool HasManagedCapability, PasskeyDeviceConfiguration DeviceConfiguration,
    PasskeyAuthorizationState AuthorizationState) : Query<PasskeyAccessVerdict> {
    #region Variables

    /// The managed capability comes first, then device setup, then consent.
    internal PasskeyAccessStatus Status {
        get {
            ArgumentNullException.ThrowIfNull(DeviceConfiguration);
            ArgumentNullException.ThrowIfNull(AuthorizationState);
            if (!HasManagedCapability) return PasskeyAccessStatus.ManagedCapabilityRequired;
            if (DeviceConfiguration.RulesOutPasskeys) return PasskeyAccessStatus.DeviceNotConfigured;
            return AuthorizationState.AccessStatus;
        }
    }

    #endregion

    #region Actions - Answering

    internal override PasskeyAccessVerdict Answer(OdeApp app) {
        return new(Status);
    }

    #endregion
}
