using OdeCore.Contracts;

namespace OdeCore.Domain;

/// A scheme Ode decides about itself: whether the engine keeps a request in
/// it or nothing may load it, for a request web content made and for a load
/// Ode itself initiated. A scheme no member names belongs to another
/// application.
public sealed class UrlScheme {
    #region Static Variables

    public const int MaximumSchemeLength = 256;

    public static readonly UrlScheme Http = new(WebScheme.Http.Name, ExternalSchemeDisposition.Engine);
    public static readonly UrlScheme Https = new(WebScheme.Https.Name, ExternalSchemeDisposition.Engine);
    public static readonly UrlScheme About = new("about", ExternalSchemeDisposition.Engine);
    public static readonly UrlScheme Blob = new("blob", ExternalSchemeDisposition.Engine);
    public static readonly UrlScheme ChromeExtension = new(AddressResolution.ChromeExtensionScheme, ExternalSchemeDisposition.Engine);
    public static readonly UrlScheme OdeExtension = new("crest-extension", ExternalSchemeDisposition.Engine);
    /// The engine, not Ode, refuses a top-level `data:` navigation from web
    /// content; handing one to another app would walk around that.
    public static readonly UrlScheme Data = new("data", ExternalSchemeDisposition.Engine);
    public static readonly UrlScheme WebKitExtension = new("webkit-extension", ExternalSchemeDisposition.Engine);
    /// May never load and may never reach another application.
    public static readonly UrlScheme JavaScript = new("javascript", ExternalSchemeDisposition.Blocked);
    /// Kept only for a load Ode itself initiated: web content asking for a
    /// file URL is asking to read the person's disk.
    public static readonly UrlScheme File = new("file", ExternalSchemeDisposition.Blocked,
        appInitiatedDisposition: ExternalSchemeDisposition.Engine);

    public static IReadOnlyList<UrlScheme> All { get; } =
        [Http, Https, About, Blob, ChromeExtension, OdeExtension, Data, WebKitExtension, JavaScript, File];

    #endregion

    #region Variables

    /// The scheme as a URL spells it, in lowercase.
    public string Name { get; }

    /// What becomes of a request in the scheme that web content made.
    public ExternalSchemeDisposition Disposition { get; }

    /// What becomes of a load in the scheme that Ode itself initiated.
    public ExternalSchemeDisposition AppInitiatedDisposition { get; }

    #endregion

    #region Constructors

    private UrlScheme(string name, ExternalSchemeDisposition disposition, ExternalSchemeDisposition? appInitiatedDisposition = null) {
        Name = name;
        Disposition = disposition;
        AppInitiatedDisposition = appInitiatedDisposition ?? disposition;
    }

    #endregion

    #region Actions - Lookup

    public static UrlScheme? Named(string? name) => All.FirstOrDefault(scheme => scheme.Name == name);

    #endregion

    #region Actions - Schemes

    /// A request the engine built without a scheme stays the engine's to
    /// resolve; one in a scheme Ode decides about goes as the scheme says,
    /// and any other belongs to another application.
    public static ExternalSchemeDisposition DispositionOf(string? scheme, bool isAppInitiated) {
        if (string.IsNullOrEmpty(scheme)) return ExternalSchemeDisposition.Engine;
        if (scheme.Length > MaximumSchemeLength) return ExternalSchemeDisposition.Blocked;
        if (Named(scheme.ToLowerInvariant()) is not { } known) return ExternalSchemeDisposition.HandOff;
        return isAppInitiated ? known.AppInitiatedDisposition : known.Disposition;
    }

    #endregion
}
