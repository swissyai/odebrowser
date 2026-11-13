namespace OdeCore.Contracts;

/// Whether Ode takes the address.
public sealed record ExternalAddressVerdict(bool Accepted);

/// Who owns the navigation.
public sealed record SchemeHandled(ExternalSchemeDisposition Disposition);
