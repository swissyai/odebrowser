import Foundation
import Security

/// The AES key Chromium's v10 scheme encrypts cookie values with for Ode's
/// own Chromium. Arc's comes from the Keychain secret the import reads once.
enum ChromiumSafeStorageKey {
    // MARK: - Static Variables

    /// The engine keeps its secret under Chromium's own names, the ones its
    /// keychain patch falls back to for a bundle outside Ode's.
    static let service = "Chromium Safe Storage"
    static let account = "Chromium"

    // MARK: - Actions - Keys

    /// The key Ode's Chromium reads, from the secret it keeps in the
    /// Keychain; when there is none yet, a new secret made the way Chromium
    /// makes one, which the engine then finds and adopts.
    static func ode() throws -> Data {
        try ChromiumPasswordCrypto.key(safeStorageSecret: try storedSecret() ?? createdSecret())
    }

    // MARK: - Actions - Keychain

    private static func storedSecret() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
            let data = result as? Data,
            let secret = String(data: data, encoding: .utf8),
            !secret.isEmpty
        else {
            throw BrowserPasswordImportError.safeStorageUnavailable
        }
        return secret
    }

    /// Chromium's secret is sixteen random bytes, kept as their base64 text.
    private static func createdSecret() throws -> String {
        var bytes = Data(count: 16)
        let generated = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard generated == errSecSuccess else {
            throw BrowserPasswordImportError.safeStorageUnavailable
        }
        let secret = bytes.base64EncodedString()
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: Data(secret.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem, let stored = try storedSecret() {
            return stored
        }
        guard status == errSecSuccess else {
            throw BrowserPasswordImportError.safeStorageUnavailable
        }
        return secret
    }
}
