using OdeCore.Application;

namespace OdeCore.Contracts;

/// How to compose a generated password of `Length` characters, or of the
/// default length when it is null. The password itself never exists in the core.
public sealed record StrongPassword(int? Length) : Query<StrongPasswordRecipe> {
    #region Actions - Answering

    internal override StrongPasswordRecipe Answer(OdeApp app) {
        return StrongPasswordRecipe.For(Length);
    }

    #endregion
}
