import Foundation
import Security

/// Keeps the ChatGPT credential as JSON in the Keychain, on this device only.
/// Nothing here is written to a file or a log.
enum ChatGPTCredentialStore {
    // MARK: - Static Variables

    static let service = "\(ProductIdentity.serviceNamespace).chatgpt"
    private static let credentialAccount = "credential"
    private static let hostAccount = "host-id"
    private static let pendingClientAccount = "pending-client-id"

    // MARK: - Types

    enum Failure: LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                String(localized: "The Keychain couldn’t save your ChatGPT sign-in (\(Int(status))).")
            }
        }
    }

    // MARK: - Actions - Credential

    static func load() -> ChatGPTCredential? {
        guard let data = read(account: credentialAccount) else { return nil }
        return try? JSONDecoder().decode(ChatGPTCredential.self, from: data)
    }

    static func save(_ credential: ChatGPTCredential) throws {
        var credential = credential
        credential.savedAt = .now
        try write(JSONEncoder().encode(credential), account: credentialAccount)
    }

    /// Drops the tokens and what they were granted, and keeps the issued
    /// client id and the ID token so the next sign-in reuses the registration.
    static func signOut() throws {
        guard var credential = load() else { return }
        credential.accessToken = nil
        credential.refreshToken = nil
        credential.expiresAt = nil
        credential.scopes = []
        try save(credential)
    }

    // MARK: - Actions - Registration

    /// A client id the server issued to a sign-in that has not finished yet.
    /// The next sign-in reuses it rather than registering Ode again.
    static func pendingClientID() -> String? {
        read(account: pendingClientAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func savePendingClientID(_ clientID: String) throws {
        try write(Data(clientID.utf8), account: pendingClientAccount)
    }

    static func clearPendingClientID() {
        SecItemDelete(query(account: pendingClientAccount) as CFDictionary)
    }

    // MARK: - Actions - Host

    /// The id this installation presents as its agent host, created on first
    /// use and the same on every sign-in after it.
    static func hostID() throws -> String {
        if let data = read(account: hostAccount), let saved = String(data: data, encoding: .utf8) {
            return saved
        }
        let created = "urn:uuid:\(UUID().uuidString.lowercased())"
        try write(Data(created.utf8), account: hostAccount)
        return created
    }

    // MARK: - Actions - Keychain

    private static func query(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    private static func read(account: String) -> Data? {
        var lookup = query(account: account)
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, account: String) throws {
        let item = query(account: account)
        let status = SecItemUpdate(item as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.keychain(status) }
        var attributes = item
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
    }
}
