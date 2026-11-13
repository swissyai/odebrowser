namespace OdeCore.Contracts;

/// The server as the prompt names it, or null when the challenge has no host
/// and the platform names Ode itself.
public sealed record AuthenticationSourceLabel(string? Label);

/// How the challenge is answered.
public sealed record ChallengeHandled(AuthenticationHandling Handling);

/// How one authentication challenge is answered.
public enum AuthenticationHandling { PromptForCredentials, PerformDefaultHandling, Cancel }
