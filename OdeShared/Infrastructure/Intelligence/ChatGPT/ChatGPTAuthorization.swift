import CryptoKit
import Foundation
import Security

/// Sign in with ChatGPT for an app that runs on the person's own device: an
/// authorization code flow with PKCE through the system browser and a
/// loopback redirect, registering this installation as an agent on first use.
/// One instance serializes sign-in and refresh, because a refresh token
/// changes each time it is used.
actor ChatGPTAuthorization {
    // MARK: - Static Variables

    static let shared = ChatGPTAuthorization()
    static let issuer = "https://auth.openai.com"
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    /// The client id that asks the server to register a new agent client.
    static let registrationClientID = "dynamic_agent_client"
    static let agentName = "Ode"
    static let resource = "https://api.openai.com/v1"
    static let planScope = "chatgpt.tokens.use.direct"
    static let offlineScope = "offline_access"
    static let scopes = ["openid", "profile", "email", offlineScope, "resource.invoke", planScope]
    static let preferredPort: UInt16 = 1455
    static let callbackPath = "/auth/callback"
    /// An access token this close to expiry is refreshed before it is used.
    static let refreshMargin: TimeInterval = 120
    static let signInTimeout: TimeInterval = 300
    /// Seconds of clock difference an ID token's times may carry.
    static let clockTolerance: TimeInterval = 5
    /// Refresh errors after which the saved tokens can never work again.
    static let unusableRefreshCodes: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused",
    ]

    // MARK: - Types

    enum Failure: LocalizedError, Equatable {
        case signedOut
        case denied
        case authorization(String)
        case registrationIncomplete
        case accountMismatch
        case invalidTokenResponse
        case unexpectedStatus(Int)
        case invalidIDToken
        case identityUnavailable
        case listener
        case timedOut

        var errorDescription: String? {
            switch self {
            case .signedOut:
                String(localized: "Continue with ChatGPT in Settings to use your plan.")
            case .denied:
                String(localized: "ChatGPT sign-in was cancelled.")
            case .authorization(let code):
                String(localized: "ChatGPT sign-in failed: \(code).")
            case .registrationIncomplete:
                String(localized: "ChatGPT didn’t finish registering Ode. Try signing in again.")
            case .accountMismatch:
                String(
                    localized:
                        "This sign-in returned a different ChatGPT account. Sign out first to use another account.")
            case .invalidTokenResponse:
                String(localized: "ChatGPT returned incomplete credentials. Try signing in again.")
            case .unexpectedStatus(let status):
                String(localized: "ChatGPT sign-in answered with status \(status).")
            case .invalidIDToken:
                String(localized: "ChatGPT’s sign-in token couldn’t be verified.")
            case .identityUnavailable:
                String(localized: "ChatGPT can’t verify sign-ins right now. Try again shortly.")
            case .listener:
                String(localized: "Ode couldn’t listen for the ChatGPT sign-in on this Mac.")
            case .timedOut:
                String(localized: "ChatGPT sign-in took too long. Try again.")
            }
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let tokenType: String?
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Double?
        let scope: String?
    }

    /// What a token response granted, once it checks out.
    private struct Grant {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
        let scopes: [String]
    }

    private struct TokenHeader: Decodable {
        let alg: String
        let kid: String?
    }

    private struct TokenClaims: Decodable {
        let iss: String
        let sub: String
        let aud: [String]
        let azp: String?
        let exp: Double
        let iat: Double
        let nonce: String?
        let email: String?

        private enum CodingKeys: String, CodingKey {
            case iss, sub, aud, azp, exp, iat, nonce, email
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            iss = try container.decode(String.self, forKey: .iss)
            sub = try container.decode(String.self, forKey: .sub)
            // An audience is either one client id or a list of them.
            if let single = try? container.decode(String.self, forKey: .aud) {
                aud = [single]
            } else {
                aud = try container.decode([String].self, forKey: .aud)
            }
            azp = try container.decodeIfPresent(String.self, forKey: .azp)
            exp = try container.decode(Double.self, forKey: .exp)
            iat = try container.decode(Double.self, forKey: .iat)
            nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
            email = try container.decodeIfPresent(String.self, forKey: .email)
        }
    }

    private struct KeySet: Decodable {
        struct Key: Decodable {
            let kty: String
            let kid: String?
            let n: String?
            let e: String?
        }

        let keys: [Key]
    }

    /// The issuer's published configuration, of which Ode uses the key set
    /// and the revocation endpoint.
    private struct Discovery: Decodable {
        let issuer: String
        let jwksUri: URL
        let revocationEndpoint: URL?
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String?
        }

        let error: String?
        let detail: Detail?

        private enum CodingKeys: String, CodingKey {
            case error
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // OAuth answers {"error": "code"}; the API answers {"error": {"code": ...}}.
            error = try? container.decode(String.self, forKey: .error)
            detail = try? container.decode(Detail.self, forKey: .error)
        }

        var code: String? { error ?? detail?.code }
    }

    // MARK: - Variables

    private var refreshTask: Task<ChatGPTCredential, any Error>?
    private var discovered: Discovery?

    // MARK: - Actions - Sign In

    /// Runs one sign-in: listens on the loopback address, opens the
    /// authorization page with `openPage`, and exchanges the code it gets back.
    /// A sign-in for an account already registered here must return that
    /// account; a different one is refused rather than replacing it.
    func signIn(opening openPage: @escaping @MainActor @Sendable (URL) -> Void) async throws -> ChatGPTCredential {
        let saved = ChatGPTCredentialStore.load()
        let registered = saved?.clientID ?? ChatGPTCredentialStore.pendingClientID()
        let hostID = try ChatGPTCredentialStore.hostID()
        let state = Self.randomToken()
        let nonce = Self.randomToken()
        let verifier = Self.randomToken()

        let listener = ChatGPTLoopbackListener(state: state)
        defer { listener.stop() }
        let port = try await listener.start(preferring: Self.preferredPort)
        let redirectURI = "http://127.0.0.1:\(port)\(Self.callbackPath)"

        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: registered ?? Self.registrationClientID),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "resource", value: Self.resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if registered == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: Self.agentName))
        }
        // Saved tokens stay out of the address; the email only preselects the account.
        if let email = saved?.email {
            items.append(URLQueryItem(name: "login_hint", value: email))
        }
        components.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name, value: $0.value.map(Self.formEncoded))
        }
        await openPage(components.url!)

        let reply = try await listener.callback(timeout: Self.signInTimeout)
        if let error = reply["error"] {
            throw error == "access_denied" ? Failure.denied : Failure.authorization(error)
        }
        guard let code = reply["code"] else { throw Failure.authorization("missing_code") }
        let returned = reply["client_id"]
        let clientID = returned ?? registered
        guard
            let clientID, clientID != Self.registrationClientID, Self.isClientID(clientID),
            registered == nil || returned == nil || returned == registered
        else { throw Failure.registrationIncomplete }
        // Kept before the one-time code is spent, so a failed exchange signs
        // in again with this registration instead of making another.
        if registered == nil { try ChatGPTCredentialStore.savePendingClientID(clientID) }

        let tokens = try await Self.token([
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", redirectURI),
            ("resource", Self.resource),
        ])
        guard let idToken = tokens.idToken, !idToken.isEmpty else { throw Failure.invalidIDToken }
        let claims = try await verifiedClaims(of: idToken, clientID: clientID, nonce: nonce)
        if let saved, saved.subject != claims.sub { throw Failure.accountMismatch }
        let grant = try Self.grant(from: tokens, previousScopes: nil, requiresRefreshToken: false)
        let credential = ChatGPTCredential(
            email: claims.email, issuer: claims.iss, subject: claims.sub, clientID: clientID, hostID: hostID,
            idToken: idToken, accessToken: grant.accessToken, refreshToken: grant.refreshToken,
            expiresAt: grant.expiresAt, scopes: grant.scopes, savedAt: .now)
        try ChatGPTCredentialStore.save(credential)
        ChatGPTCredentialStore.clearPendingClientID()
        return credential
    }

    // MARK: - Actions - Sign Out

    /// Revokes the refresh token with OpenAI and then forgets the tokens on
    /// this Mac whatever the answer. Answers whether OpenAI confirmed it; when
    /// it did not, the person can still disconnect Ode in ChatGPT's settings.
    func signOut() async -> Bool {
        refreshTask?.cancel()
        refreshTask = nil
        let credential = ChatGPTCredentialStore.load()
        var revoked = credential?.refreshToken == nil
        if let credential, let refreshToken = credential.refreshToken,
            let endpoint = try? await discovery().revocationEndpoint
        {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody([
                ("token", refreshToken), ("token_type_hint", "refresh_token"), ("client_id", credential.clientID),
            ])
            let status = try? await (ChatGPTNetwork.session.data(for: request).1 as? HTTPURLResponse)?.statusCode
            revoked = status == 200
        }
        try? ChatGPTCredentialStore.signOut()
        return revoked
    }

    // MARK: - Actions - Refresh

    /// The saved credential with an access token that is good for now,
    /// refreshed first when it has expired or is about to.
    func currentCredential() async throws -> ChatGPTCredential {
        guard let credential = ChatGPTCredentialStore.load(), credential.isSignedIn else {
            throw Failure.signedOut
        }
        if credential.accessToken != nil, let expiry = credential.expiresAt, expiry > .now + Self.refreshMargin {
            return credential
        }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.refreshed(credential) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Replaces the access token, its expiry, its scopes and the refresh
    /// token together. A refresh token the server says can never work again,
    /// or an identity that is no longer this account's, signs the person out;
    /// any other failure keeps the saved tokens for a later try.
    private func refreshed(_ credential: ChatGPTCredential) async throws -> ChatGPTCredential {
        guard let refreshToken = credential.refreshToken else { throw Failure.signedOut }
        do {
            let tokens = try await Self.token([
                ("grant_type", "refresh_token"),
                ("client_id", credential.clientID),
                ("refresh_token", refreshToken),
                ("resource", Self.resource),
            ])
            // A refresh may leave the scope out when what was granted is unchanged.
            let grant = try Self.grant(from: tokens, previousScopes: credential.scopes, requiresRefreshToken: true)
            var updated = credential
            if let idToken = tokens.idToken {
                let claims = try await verifiedClaims(of: idToken, clientID: credential.clientID, nonce: nil)
                guard claims.sub == credential.subject else { throw Failure.accountMismatch }
                updated.idToken = idToken
                updated.email = claims.email ?? credential.email
            }
            updated.accessToken = grant.accessToken
            updated.refreshToken = grant.refreshToken
            updated.expiresAt = grant.expiresAt
            updated.scopes = grant.scopes
            try ChatGPTCredentialStore.save(updated)
            return updated
        } catch let failure as Failure {
            switch failure {
            case .authorization(let code) where Self.unusableRefreshCodes.contains(code):
                try? ChatGPTCredentialStore.signOut()
                throw Failure.signedOut
            case .accountMismatch, .invalidIDToken, .invalidTokenResponse:
                try? ChatGPTCredentialStore.signOut()
                throw failure
            default:
                throw failure
            }
        }
    }

    // MARK: - Actions - Tokens

    /// Posts a form-encoded grant to the token endpoint. A public client
    /// sends no secret. A refusal carries the server's error code.
    private static func token(_ fields: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(fields)
        let (data, response) = try await ChatGPTNetwork.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            if let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.code {
                throw Failure.authorization(code)
            }
            throw Failure.unexpectedStatus(status)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tokens = try? decoder.decode(TokenResponse.self, from: data) else {
            throw Failure.invalidTokenResponse
        }
        return tokens
    }

    /// The tokens a response granted, refusing one without a bearer access
    /// token, a positive lifetime, its granted scopes, or the refresh token
    /// offline access promises.
    private static func grant(
        from tokens: TokenResponse, previousScopes: [String]?, requiresRefreshToken: Bool
    ) throws -> Grant {
        guard
            let scope = tokens.scope.map(scopeList) ?? previousScopes,
            let accessToken = tokens.accessToken, !accessToken.isEmpty,
            tokens.tokenType?.lowercased() == "bearer",
            let lifetime = tokens.expiresIn, lifetime > 0, lifetime.isFinite
        else { throw Failure.invalidTokenResponse }
        let refreshToken = tokens.refreshToken.flatMap { $0.isEmpty ? nil : $0 }
        if refreshToken == nil, requiresRefreshToken || scope.contains(offlineScope) {
            throw Failure.invalidTokenResponse
        }
        return Grant(accessToken: accessToken, refreshToken: refreshToken, expiresAt: .now + lifetime, scopes: scope)
    }

    /// The ID token's claims once its RS256 signature checks out against the
    /// issuer's published keys and it names this client, this sign-in's nonce
    /// when there is one, and a time that hasn't passed. A key set that can't
    /// be fetched is an outage, not a bad token.
    private func verifiedClaims(of idToken: String, clientID: String, nonce: String?) async throws -> TokenClaims {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            let headerData = Self.base64URLDecoded(parts[0]),
            let claimsData = Self.base64URLDecoded(parts[1]),
            let signature = Self.base64URLDecoded(parts[2]),
            let header = try? JSONDecoder().decode(TokenHeader.self, from: headerData),
            header.alg == "RS256",
            let claims = try? JSONDecoder().decode(TokenClaims.self, from: claimsData),
            claims.iss == Self.issuer,
            !claims.sub.isEmpty,
            claims.aud.contains(clientID),
            claims.azp == nil || claims.azp == clientID,
            claims.aud.count == 1 || claims.azp == clientID,
            Date(timeIntervalSince1970: claims.exp + Self.clockTolerance) > .now,
            nonce == nil || claims.nonce == nonce
        else { throw Failure.invalidIDToken }

        let keys: [KeySet.Key]
        do {
            let (keyData, response) = try await ChatGPTNetwork.session.data(from: try await discovery().jwksUri)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.identityUnavailable }
            keys = try JSONDecoder().decode(KeySet.self, from: keyData).keys.filter { $0.kty == "RSA" }
        } catch {
            throw Failure.identityUnavailable
        }
        let match: KeySet.Key? =
            if let kid = header.kid { keys.first { $0.kid == kid } } else { keys.count == 1 ? keys.first : nil }
        guard let jwk = match else { throw Failure.identityUnavailable }
        guard
            let modulus = jwk.n.flatMap({ Self.base64URLDecoded($0) }),
            let exponent = jwk.e.flatMap({ Self.base64URLDecoded($0) }),
            let key = SecKeyCreateWithData(
                Self.rsaPublicKeyDER(modulus: modulus, exponent: exponent) as CFData,
                [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary,
                nil),
            SecKeyVerifySignature(
                key, .rsaSignatureMessagePKCS1v15SHA256, Data("\(parts[0]).\(parts[1])".utf8) as CFData,
                signature as CFData, nil)
        else { throw Failure.invalidIDToken }
        return claims
    }

    /// The issuer's configuration, read once per launch and trusted only when
    /// it names this issuer and keeps its endpoints on the issuer's origin.
    private func discovery() async throws -> Discovery {
        if let discovered { return discovered }
        let (data, response) = try await ChatGPTNetwork.session.data(from: Self.discoveryURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard
            (response as? HTTPURLResponse)?.statusCode == 200,
            let configuration = try? decoder.decode(Discovery.self, from: data),
            configuration.issuer == Self.issuer,
            Self.isIssuerOrigin(configuration.jwksUri),
            configuration.revocationEndpoint.map(Self.isIssuerOrigin) ?? true
        else { throw Failure.identityUnavailable }
        discovered = configuration
        return configuration
    }

    // MARK: - Actions - Encoding

    /// 32 random bytes as base64url, for a state, a nonce or a PKCE verifier.
    private static func randomToken() -> String {
        base64URLEncoded(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    private static func challenge(for verifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func isClientID(_ value: String) -> Bool {
        (1...200).contains(value.count)
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    private static func isIssuerOrigin(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "auth.openai.com" && url.port == nil
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ text: some StringProtocol) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func formEncoded(_ value: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func formBody(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\(formEncoded($0))=\(formEncoded($1))" }.joined(separator: "&").utf8)
    }

    private static func scopeList(_ scope: String) -> [String] {
        scope.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// A PKCS #1 RSAPublicKey, `SEQUENCE { modulus INTEGER, publicExponent
    /// INTEGER }` in DER, which is the form `SecKeyCreateWithData` reads.
    static func rsaPublicKeyDER(modulus: Data, exponent: Data) -> Data {
        func element(_ tag: UInt8, _ content: Data) -> Data {
            var length = [UInt8]()
            if content.count < 0x80 {
                length = [UInt8(content.count)]
            } else {
                var count = content.count
                while count > 0 {
                    length.insert(UInt8(count & 0xFF), at: 0)
                    count >>= 8
                }
                length.insert(0x80 | UInt8(length.count), at: 0)
            }
            return Data([tag] + length) + content
        }
        // A DER integer is signed, so an unsigned value with its top bit set
        // needs a leading zero byte.
        func integer(_ bytes: Data) -> Data {
            var value = [UInt8](bytes.drop(while: { $0 == 0 }))
            if value.isEmpty || value[0] & 0x80 != 0 { value.insert(0, at: 0) }
            return element(0x02, Data(value))
        }
        return element(0x30, integer(modulus) + integer(exponent))
    }
}
