import Foundation

/// What a Sign in with ChatGPT leaves behind. The tokens are present only
/// while the person is signed in.
struct ChatGPTCredential: Codable, Equatable, Sendable {
    // MARK: - Variables

    var email: String?
    var issuer: String
    var subject: String
    /// The client id the authorization server issued at first registration.
    var clientID: String
    var hostID: String
    var idToken: String
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?
    var scopes: [String]
    var savedAt: Date

    var isSignedIn: Bool { accessToken != nil || refreshToken != nil }
}
