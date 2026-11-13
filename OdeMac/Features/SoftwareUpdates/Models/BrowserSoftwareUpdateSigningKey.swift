import CryptoKit
import Foundation

/// Ode's EdDSA public key for updates (`SUPublicEDKey`). Every feed and disk
/// image Ode installs carries a signature made with its private key, which
/// Sparkle checks for updates and Ode checks again before going back to an
/// earlier version.
struct BrowserSoftwareUpdateSigningKey: Sendable {
    // MARK: - Static Variables

    /// The key this copy of Ode trusts, from its Info.plist.
    static var bundled: Self? {
        (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).flatMap(Self.init(base64:))
    }

    /// The comment Sparkle appends to a signed feed: the signature and how
    /// many bytes before it the signature covers.
    private static let feedSignature = try! NSRegularExpression(
        pattern: #"<!-- sparkle-signatures:\s*\nedSignature: ([A-Za-z0-9+/=]+)\s*\nlength: ([0-9]+)\s*\n-->\s*$"#)

    // MARK: - Variables

    private let key: Curve25519.Signing.PublicKey

    // MARK: - Initializers

    init?(base64: String) {
        guard let raw = Data(base64Encoded: base64), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { return nil }
        self.key = key
    }

    // MARK: - Actions - Verifying

    /// Whether `signature`, base64 as a feed spells it, signs `data`.
    func isValid(signature: String, for data: Data) -> Bool {
        guard let signature = Data(base64Encoded: signature) else { return false }
        return key.isValidSignature(signature, for: data)
    }

    /// Whether `feed` carries a valid signature of its own over everything
    /// before the signature, as Sparkle requires of Ode's feeds.
    func isValidFeed(_ feed: Data) -> Bool {
        guard let text = String(data: feed, encoding: .utf8),
            let match = Self.feedSignature.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let signatureRange = Range(match.range(at: 1), in: text),
            let lengthRange = Range(match.range(at: 2), in: text),
            let length = Int(text[lengthRange]), length > 0, length <= feed.count
        else { return false }
        return isValid(signature: String(text[signatureRange]), for: feed.prefix(length))
    }
}
