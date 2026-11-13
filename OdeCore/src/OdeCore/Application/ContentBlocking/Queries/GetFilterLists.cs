using OdeCore.Application;

namespace OdeCore.Contracts;

/// Every filter list as the settings show it, and the person's own filters.
public sealed record GetFilterLists : Query<FilterLists> {
    #region Actions - Answering

    internal override FilterLists Answer(OdeApp app) => app.Filters.States();

    #endregion
}
