using OdeCore.Contracts;

namespace OdeCore.Domain;

/// Where Shift-Return takes a search: straight to its first result, through
/// the search syntax DuckDuckGo documents for it, a backslash before the
/// query, or Kagi's same syntax when Kagi is the engine. The tab loads that
/// address and follows the engine's redirect itself; nothing reads the
/// results in the background, so the engine sees an ordinary search the
/// person ran.
internal static class TopResult {
    #region Static Variables

    /// What the engines read as "go to the first result".
    private const string FirstResultSign = "\\";

    #endregion

    #region Actions - Resolving

    /// The address that opens the first result for `query` searched with
    /// `engine`, or null when `engine` is an assistant or a website, which
    /// have no first result, or nothing was typed. Kagi finds it itself, a
    /// DuckDuckGo engine keeps its own options, and every other engine goes
    /// through DuckDuckGo as `catalog` keeps it, with the person's region and
    /// safe search.
    public static string? Address(SearchProvider engine, SearchCatalog catalog, string query) {
        ArgumentNullException.ThrowIfNull(engine);
        ArgumentNullException.ThrowIfNull(catalog);
        ArgumentNullException.ThrowIfNull(query);
        string trimmed = query.Trim();
        if (trimmed.Length == 0 || engine.Kind != SearchProviderKind.Engine) return null;
        var finder = engine.BuiltIn == BuiltInSearchProvider.Kagi || engine.BuiltIn == BuiltInSearchProvider.DuckDuckGo
            ? engine : catalog.Resolving(BuiltInSearchProvider.DuckDuckGo);
        return finder.Search(FirstResultSign + trimmed);
    }

    #endregion
}
