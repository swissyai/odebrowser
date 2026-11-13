using OdeCore.Application;

namespace OdeCore.Contracts;

/// The host's isolated bridge reports only trusted-edit metadata, never field
/// values. Reports from a replaced engine or a released page change nothing.
public sealed record ReportPageDraft(Guid PageId, EngineKind Engine, bool IsMainFrame, bool HoldsTypedText) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        if (pages.Hosted(PageId) is not { } page || page.Engine.Kind != Engine || !page.Phase.HoldsEnginePage) return;
        page.ReportDraft(IsMainFrame, HoldsTypedText);
    }

    #endregion
}
