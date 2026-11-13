namespace OdeCore.Contracts;

/// The scheme an authentication challenge asks for, and whether Ode answers
/// it with its own credential prompt. A method travels as its index in `All`,
/// so `All` is append-only.
public sealed class AuthenticationMethod {
    #region Static Variables

    public static readonly AuthenticationMethod HttpBasic = new(name: "httpBasic", promptsForCredentials: true);
    public static readonly AuthenticationMethod HttpDigest = new(name: "httpDigest", promptsForCredentials: true);
    /// Any scheme Ode leaves to the system, such as a server trust or a
    /// client certificate challenge.
    public static readonly AuthenticationMethod Other = new(name: "other", promptsForCredentials: false);

    public static IReadOnlyList<AuthenticationMethod> All { get; } = [HttpBasic, HttpDigest, Other];

    #endregion

    #region Variables

    public string Name { get; }

    /// Ode answers the challenge with its own prompt for a username and
    /// password; otherwise the system handles it.
    public bool PromptsForCredentials { get; }

    #endregion

    #region Constructors

    private AuthenticationMethod(string name, bool promptsForCredentials) {
        Name = name;
        PromptsForCredentials = promptsForCredentials;
    }

    #endregion

    #region Actions - Lookup

    public static AuthenticationMethod? Named(string? name) => All.FirstOrDefault(method => method.Name == name);

    #endregion
}
