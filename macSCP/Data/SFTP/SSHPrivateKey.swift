//
//  SSHPrivateKey.swift
//  macSCP
//
//  Loads OpenSSH/PEM private keys for Citadel, detecting the key type.
//  Shared by the SFTP and terminal sessions.
//

import Foundation
import Citadel
import Crypto

enum SSHPrivateKeyType: String {
    case ed25519
    case rsa
}

struct LoadedSSHPrivateKey {
    let authenticationMethod: SSHAuthenticationMethod
    let type: SSHPrivateKeyType
}

enum SSHPrivateKey {
    /// Parses private key text into a Citadel authentication method. Tries
    /// ed25519 first (today's `ssh-keygen` default), then RSA.
    static func load(username: String, keyText: String, passphrase: String?) throws -> LoadedSSHPrivateKey {
        let decryptionKey = passphrase.flatMap { $0.isEmpty ? nil : $0.data(using: .utf8) }

        if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: keyText, decryptionKey: decryptionKey) {
            return LoadedSSHPrivateKey(
                authenticationMethod: .ed25519(username: username, privateKey: key),
                type: .ed25519
            )
        }
        if let key = try? Insecure.RSA.PrivateKey(sshRsa: keyText, decryptionKey: decryptionKey) {
            return LoadedSSHPrivateKey(
                authenticationMethod: .rsa(username: username, privateKey: key),
                type: .rsa
            )
        }
        throw AppError.connectionFailed(unreadableKeyMessage(keyText: keyText, hasPassphrase: decryptionKey != nil))
    }

    private static func unreadableKeyMessage(keyText: String, hasPassphrase: Bool) -> String {
        if keyText.contains("EC PRIVATE KEY") || keyText.lowercased().contains("ecdsa") {
            return "ECDSA private keys are not supported — use an ed25519 or RSA key."
        }
        if hasPassphrase {
            return "The private key could not be decrypted with the given passphrase."
        }
        return "The private key could not be read. Supported formats: OpenSSH or PEM ed25519/RSA keys. "
            + "If the key is passphrase-protected, enter the passphrase when connecting."
    }

    /// Explains an authentication rejection. RSA gets an extra hint because
    /// Citadel signs with legacy ssh-rsa (SHA-1), which OpenSSH 8.8+ servers
    /// refuse by default.
    static func rejectionMessage(for type: SSHPrivateKeyType, username: String, host: String) -> String {
        var message = "The server rejected the private key for \(username)@\(host). "
            + "Check that its public key is in that user's authorized_keys."
        if type == .rsa {
            message += " Note: this app signs RSA keys with the legacy ssh-rsa (SHA-1) algorithm, "
                + "which OpenSSH 8.8+ servers disable by default — an ed25519 key avoids this."
        }
        return message
    }
}
