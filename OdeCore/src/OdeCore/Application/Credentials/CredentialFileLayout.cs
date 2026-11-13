using OdeCore.Contracts;

namespace OdeCore.Application;

/// Where a password file's header row puts its columns: how many it names,
/// and which hold the site, the username, the password and, when the file
/// has one, the account's name. A row reads through it into a credential or
/// the flaw that leaves the row out.
internal sealed record CredentialFileLayout(int Width, int Site, int Username, int Password, int? Name) {
    #region Constructors

    /// The layout `headers` name, as `CredentialFileColumn.Normalized` spells
    /// them. Throws `Rejected` with `InvalidCredentialFile` for a required
    /// column that is missing or named twice.
    public static CredentialFileLayout Of(IReadOnlyList<string> headers) => new(headers.Count,
        CredentialFileColumn.Site.Index(headers)!.Value, CredentialFileColumn.Username.Index(headers)!.Value,
        CredentialFileColumn.Password.Index(headers)!.Value, CredentialFileColumn.Name.Index(headers));

    #endregion

    #region Actions - Rows

    /// The credential `row` holds as row `rowNumber`, or the flaw that leaves
    /// it out: more fields than the header names, a site that is no web
    /// address, or an empty password. Missing trailing fields read as empty.
    public (ImportedCredential? Credential, CredentialRowFlaw? Flaw) Read(IReadOnlyList<string> row, int rowNumber) {
        if (row.Count > Width) return (null, CredentialRowFlaw.MalformedRow);
        string Field(int column) => column < row.Count ? row[column] : "";
        if (CredentialFile.Origin(Field(Site).Trim()) is not { } origin) return (null, CredentialRowFlaw.InvalidOrigin);
        string secret = Field(Password);
        if (secret.Length == 0) return (null, CredentialRowFlaw.EmptyPassword);
        string? displayName = Name is { } column && Field(column) is { Length: > 0 } named ? named : null;
        return (new(rowNumber, displayName, origin, Field(Username), secret), null);
    }

    #endregion
}
