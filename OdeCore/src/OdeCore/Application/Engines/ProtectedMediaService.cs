using OdeCore.Contracts;

namespace OdeCore.Application;

/// A video service whose player plays only in an engine with the platform's
/// protected media. Ode's Chromium does not include Widevine, so these sites
/// open in an engine with platform protected media unless the person chose
/// an engine for the site. Playback still depends on the site's support.
internal sealed class ProtectedMediaService {
    #region Variables

    public static readonly ProtectedMediaService Netflix = new("netflix.com", "www.netflix.com");
    public static readonly ProtectedMediaService DisneyPlus = new("disneyplus.com", "www.disneyplus.com");
    public static readonly ProtectedMediaService Max = new("max.com", "www.max.com", "play.max.com",
        "hbomax.com", "www.hbomax.com", "play.hbomax.com");
    public static readonly ProtectedMediaService PrimeVideo = new("primevideo.com", "www.primevideo.com");

    public static IReadOnlyList<ProtectedMediaService> All { get; } = [Netflix, DisneyPlus, Max, PrimeVideo];

    /// The secure origins the service's site and player load from.
    private readonly IReadOnlyList<SiteOrigin> origins;

    #endregion

    #region Constructors

    private ProtectedMediaService(params string[] hosts) =>
        origins = [.. hosts.Select(host => new SiteOrigin("https", host, -1))];

    #endregion

    #region Actions - Lookup

    /// The service `origin` belongs to, or null for any other site.
    public static ProtectedMediaService? Serving(SiteOrigin origin) =>
        All.FirstOrDefault(service => service.origins.Contains(origin));

    #endregion
}
