using OdeCore.Application;

namespace OdeCore.Contracts;

/// The device's import attempts, including interrupted ones and extensions
/// still awaiting installation. Opening setup again does not erase them.
public sealed record GetSetupImportOutcomes : Query<SetupImportOutcomes> {
    #region Actions - Answering

    internal override SetupImportOutcomes Answer(OdeApp app) => new(app.Device.ImportOutcomes);

    #endregion
}
