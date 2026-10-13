//
//  BackupCrypto.swift
//  macSCP
//
//  Password-based encryption for backup files:
//  PBKDF2-HMAC-SHA256 (CommonCrypto) key derivation + AES-256-GCM (CryptoKit)
//

import Foundation
import CryptoKit
import CommonCrypto

enum BackupCryptoError: LocalizedError {
    case invalidFormat
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The file is not a valid macSCP-Revived backup"
        case .invalidPassword:
            return "Wrong password or the backup file has been modified"
        }
    }
}

enum BackupCrypto {
    static let kdfAlgorithm = "PBKDF2-HMAC-SHA256"
    static let cipher = "AES-256-GCM"
    static let saltLength = 16
    static let keyLength = 32
    static let nonceLength = 12
    static let gcmTagLength = 16
    /// OWASP 2023 recommendation for PBKDF2-HMAC-SHA256
    static let defaultIterations: UInt32 = 600_000

    // MARK: - Seal

    static func seal(_ plaintext: Data, password: String) throws -> BackupFileEnvelope {
        var salt = [UInt8](repeating: 0, count: saltLength)
        let saltStatus = salt.withUnsafeMutableBufferPointer { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        guard saltStatus == errSecSuccess else {
            throw BackupCryptoError.invalidFormat
        }

        let key = try deriveKey(password: password, salt: Data(salt), iterations: defaultIterations)
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintext, using: key)
        } catch {
            throw BackupCryptoError.invalidFormat
        }

        let nonceData = sealed.nonce.withUnsafeBytes { raw in
            Data(bytes: raw.baseAddress!, count: raw.count)
        }

        return BackupFileEnvelope(
            format: BackupFormat.identifier,
            version: BackupFormat.version,
            createdAt: Date(),
            kdf: BackupKDFParams(
                algorithm: kdfAlgorithm,
                iterations: Int(defaultIterations),
                salt: Data(salt).base64EncodedString()
            ),
            encryption: cipher,
            nonce: nonceData.base64EncodedString(),
            // ciphertext and GCM tag are stored appended
            data: (sealed.ciphertext + sealed.tag).base64EncodedString()
        )
    }

    // MARK: - Open

    static func open(_ envelope: BackupFileEnvelope, password: String) throws -> Data {
        guard envelope.format == BackupFormat.identifier,
              envelope.kdf.algorithm == kdfAlgorithm,
              envelope.encryption == cipher,
              envelope.kdf.iterations > 0,
              envelope.kdf.iterations <= 10_000_000,
              let salt = Data(base64Encoded: envelope.kdf.salt),
              salt.count == saltLength,
              let nonceData = Data(base64Encoded: envelope.nonce),
              nonceData.count == nonceLength,
              let ciphertextAndTag = Data(base64Encoded: envelope.data),
              ciphertextAndTag.count > gcmTagLength
        else {
            throw BackupCryptoError.invalidFormat
        }

        let key = try deriveKey(
            password: password,
            salt: salt,
            iterations: UInt32(envelope.kdf.iterations)
        )

        let tag = ciphertextAndTag.suffix(gcmTagLength)
        let ciphertext = ciphertextAndTag.dropLast(gcmTagLength)

        let box: AES.GCM.SealedBox
        let plaintext: Data
        do {
            box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw BackupCryptoError.invalidPassword
        }

        return plaintext
    }

    // MARK: - Key Derivation

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        var derivedKey = [UInt8](repeating: 0, count: keyLength)
        let passwordBytes = [UInt8](password.utf8)
        let saltBytes = [UInt8](salt)

        let status = saltBytes.withUnsafeBufferPointer { saltPointer in
            derivedKey.withUnsafeMutableBufferPointer { derivedPointer in
                passwordBytes.withUnsafeBufferPointer { passwordPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer.baseAddress!
                            .withMemoryRebound(to: Int8.self, capacity: passwordBytes.count) { $0 },
                        passwordBytes.count,
                        saltPointer.baseAddress,
                        saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedPointer.baseAddress,
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw BackupCryptoError.invalidFormat
        }

        return SymmetricKey(data: Data(derivedKey))
    }
}

// MARK: - File Codec

/// A decrypted backup: its payload plus the metadata from the file envelope
struct DecryptedBackup {
    let createdAt: Date
    let payload: BackupPayload
}

extension BackupCrypto {
    /// Encodes a payload into the encrypted file representation
    static func encode(payload: BackupPayload, password: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(payload)
        let envelope = try seal(plaintext, password: password)
        return try encoder.encode(envelope)
    }

    /// Decodes and decrypts a backup file
    static func decodeBackup(fileContents: Data, password: String) throws -> DecryptedBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupFileEnvelope.self, from: fileContents)
        let plaintext = try open(envelope, password: password)
        let payload = try decoder.decode(BackupPayload.self, from: plaintext)
        return DecryptedBackup(createdAt: envelope.createdAt, payload: payload)
    }
}
