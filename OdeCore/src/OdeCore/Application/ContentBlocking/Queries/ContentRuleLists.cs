using OdeCore.Application;

namespace OdeCore.Contracts;

/// The content rule lists a page that blocks applies now. Before any filter
/// list arrives they hold Ode's own baseline rules; `ContentRuleListsChanged`
/// names the next ones.
public sealed record ContentRuleLists : Query<ContentRuleListSet> {
    #region Actions - Answering

    internal override ContentRuleListSet Answer(OdeApp app) => app.Filters.Rules();

    #endregion
}
