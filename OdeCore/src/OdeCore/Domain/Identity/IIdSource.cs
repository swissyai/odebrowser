namespace OdeCore.Domain;

public interface IIdSource {
    #region Abstract Methods

    Guid Next();

    #endregion
}
