import CommonCrypto
import Foundation

enum ChromiumPasswordCrypto {
    static func key(safeStorageSecret: String) throws -> Data {
        let password = Data(safeStorageSecret.utf8)
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyCount = key.count
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BrowserPasswordImportError.unsupportedEncryption
        }
        return key
    }

    static func decrypt(_ encrypted: Data, key: Data) throws -> Data {
        guard encrypted.count > 3,
            encrypted.prefix(3) == Data("v10".utf8)
                || encrypted.prefix(3) == Data("v11".utf8)
        else {
            throw BrowserPasswordImportError.unsupportedEncryption
        }
        let ciphertext = encrypted.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCount = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCount,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw BrowserPasswordImportError.unsupportedEncryption
        }
        output.removeSubrange(moved..<output.count)
        return output
    }

    /// `plaintext` as Chromium's v10 scheme keeps it, which `decrypt` reads
    /// back with the same key.
    static func encrypt(_ plaintext: Data, key: Data) throws -> Data {
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        let outputCount = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            plaintext.withUnsafeBytes { plaintextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            plaintextBytes.baseAddress,
                            plaintext.count,
                            outputBytes.baseAddress,
                            outputCount,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw BrowserPasswordImportError.unsupportedEncryption
        }
        output.removeSubrange(moved..<output.count)
        return Data("v10".utf8) + output
    }
}
