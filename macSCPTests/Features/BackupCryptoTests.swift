//
//  BackupCryptoTests.swift
//  macSCPTests
//
//  Unit tests for backup encryption (PBKDF2 + AES-256-GCM)
//

import XCTest
@testable import macSCP

final class BackupCryptoTests: XCTestCase {
    private var samplePayload: BackupPayload {
        BackupPayload(
            connections: [
                Connection(
                    name: "prod",
                    host: "example.com",
                    username: "deploy",
                    savePassword: true
                )
            ],
            folders: [Folder(name: "Servers")],
            credentials: [
                BackupCredential(
                    connectionId: Connection(name: "x", host: "h", username: "u").id,
                    password: "hunter2",
                    s3Credentials: nil
                )
            ],
            settings: BackupSettings(
                isBiometricLockEnabled: true,
                lockOnAppResume: false,
                lockBeforeConnection: true,
                lockAfterInactivity: false,
                inactivityTimeout: 300
            )
        )
    }

    // MARK: - Round Trip

    func testEncodeDecodeRoundTrip() throws {
        let payload = samplePayload

        let data = try BackupCrypto.encode(payload: payload, password: "correct horse")
        let restored = try BackupCrypto.decodeBackup(fileContents: data, password: "correct horse")

        XCTAssertEqual(restored.payload.connections.map(\.name), payload.connections.map(\.name))
        XCTAssertEqual(restored.payload.folders.map(\.name), payload.folders.map(\.name))
        XCTAssertEqual(restored.payload.settings, payload.settings)
        XCTAssertEqual(restored.payload.credentials.count, 1)
    }

    func testEncodedFileIsNotPlaintext() throws {
        let data = try BackupCrypto.encode(payload: samplePayload, password: "correct horse")
        let contents = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(contents.contains("example.com"))
        XCTAssertFalse(contents.contains("hunter2"))
        XCTAssertTrue(contents.contains(BackupFormat.identifier))
    }

    // MARK: - Password & Integrity

    func testWrongPasswordThrows() throws {
        let data = try BackupCrypto.encode(payload: samplePayload, password: "correct horse")

        XCTAssertThrowsError(try BackupCrypto.decodeBackup(fileContents: data, password: "wrong")) { error in
            XCTAssertEqual(error as? BackupCryptoError, .invalidPassword)
        }
    }

    func testTamperedCiphertextThrows() throws {
        let data = try BackupCrypto.encode(payload: samplePayload, password: "correct horse")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var envelope = try decoder.decode(BackupFileEnvelope.self, from: data)

        guard var ciphertext = Data(base64Encoded: envelope.data) else {
            return XCTFail("Ciphertext is not valid base64")
        }
        ciphertext[ciphertext.count - 1] ^= 0xFF
        envelope = BackupFileEnvelope(
            format: envelope.format,
            version: envelope.version,
            createdAt: envelope.createdAt,
            kdf: envelope.kdf,
            encryption: envelope.encryption,
            nonce: envelope.nonce,
            data: ciphertext.base64EncodedString()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tampered = try encoder.encode(envelope)

        XCTAssertThrowsError(try BackupCrypto.decodeBackup(fileContents: tampered, password: "correct horse")) { error in
            XCTAssertEqual(error as? BackupCryptoError, .invalidPassword)
        }
    }

    func testGarbageInputThrows() {
        let garbage = Data("not a backup at all".utf8)
        XCTAssertThrowsError(try BackupCrypto.decodeBackup(fileContents: garbage, password: "x"))
    }
}
