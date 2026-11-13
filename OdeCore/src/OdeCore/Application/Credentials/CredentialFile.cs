using System.Text;

using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

/// A password file as the core reads it: its format, the passwords its rows
/// hold and the rows it leaves out. The first row names the columns; blank
/// rows are skipped, and the rest count from 2 in the order they appear. A
/// row's site may leave out its scheme, which is then HTTPS.
[HoldsSecrets]
internal sealed record CredentialFile(CredentialFileFormat Format, IReadOnlyList<ImportedCredential> Credentials,
    IReadOnlyList<CredentialRowRejection> Rejections) {
    #region Static Variables

    /// The largest file an import reads, in bytes.
    public const int MaximumBytes = 16 * 1024 * 1024;
    /// The most credential rows a file may hold.
    public const int MaximumRows = 10_000;
    /// The most columns a row may hold.
    public const int MaximumColumns = 64;
    /// The most characters a field may hold.
    public const int MaximumFieldCharacters = 65_536;

    private static readonly CsvReader Reader = new(new CsvLimits(MaximumRows + 1, MaximumColumns, MaximumFieldCharacters));

    #endregion

    #region Actions - Reading

    /// The file `document` holds. Throws `Rejected` with
    /// `InvalidCredentialFile` for one that cannot import at all.
    public static CredentialFile Read(byte[] document) {
        ArgumentNullException.ThrowIfNull(document);
        var rows = FilledRows(document);
        var headers = rows[0].Select(CredentialFileColumn.Normalized).ToArray();
        var layout = CredentialFileLayout.Of(headers);
        var format = CredentialFileFormat.Detected(headers.ToHashSet(StringComparer.Ordinal));
        if (rows.Count - 1 > MaximumRows) throw Invalid(CredentialFileFlaw.TooManyRows);
        if (rows.Count == 1) throw Invalid(CredentialFileFlaw.NoRows);

        var credentials = new List<ImportedCredential>(rows.Count - 1);
        var rejections = new List<CredentialRowRejection>();
        for (int index = 1; index < rows.Count; index++) {
            int rowNumber = index + 1;
            var (credential, flaw) = layout.Read(rows[index], rowNumber);
            if (credential is not null) credentials.Add(credential);
            if (flaw is not null) rejections.Add(new(rowNumber, flaw));
        }
        return new(format, credentials, rejections);
    }

    /// The rows of `document` that hold anything but blanks, the header row
    /// first. Throws `Rejected` for a file that is too large, not UTF-8 text,
    /// not CSV within the limits, or blank.
    private static IReadOnlyList<IReadOnlyList<string>> FilledRows(byte[] document) {
        if (document.Length > MaximumBytes) throw Invalid(CredentialFileFlaw.TooLarge);
        string text;
        try {
            text = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true).GetString(document);
        } catch (DecoderFallbackException) {
            throw Invalid(CredentialFileFlaw.NotText);
        }
        IReadOnlyList<IReadOnlyList<string>> rows;
        try {
            rows = Reader.Read(text);
        } catch (CsvException error) {
            throw Invalid(CredentialFileFlaw.Answering(error.Fault));
        }
        rows = [.. rows.Where(row => row.Any(field => !string.IsNullOrWhiteSpace(field)))];
        return rows.Count == 0 ? throw Invalid(CredentialFileFlaw.Empty) : rows;
    }

    /// The HTTP(S) origin `site` names, with HTTPS for a site written without
    /// a scheme, or null for one that is no web address. A host in brackets
    /// is kept as spelled, so an escaped zone ID is refused rather than read
    /// as part of the address, and it must be an IPv6 address. An IP address
    /// is spelled as a page's origin spells it, so the password fills there.
    public static CredentialOrigin? Origin(string site) {
        ArgumentNullException.ThrowIfNull(site);
        string spelled = site.Contains("://", StringComparison.Ordinal) ? site : $"https://{site}";
        if (ImportAddress.Read(spelled) is not { } address || WebScheme.Named(address.Scheme) is not { } scheme) return null;
        if (address.IPLiteral is { } literal && !literal.Contains(':', StringComparison.Ordinal)) return null;
        if (CredentialOrigin.CanonicalHost((address.IPLiteral ?? address.Host).ToLowerInvariant()) is not { } host) return null;
        var origin = new CredentialOrigin(scheme.Name, host, address.Port ?? scheme.DefaultPort);
        return origin.IsValid ? origin : null;
    }

    private static Rejected Invalid(CredentialFileFlaw flaw) => new(new InvalidCredentialFile(flaw));

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CredentialFile { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Format = {Format.Name}, Credentials = {Credentials.Count}, Rejections = {Rejections.Count}");
        return true;
    }

    #endregion
}
