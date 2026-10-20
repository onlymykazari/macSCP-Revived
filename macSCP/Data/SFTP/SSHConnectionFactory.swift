//
//  SSHConnectionFactory.swift
//  macSCP
//
//  Establishes SSH client connections with a key-exchange compatibility
//  fallback, shared by the SFTP and terminal sessions.
//

import Foundation
import Citadel
import NIO
import NIOSSH

enum SSHConnectionFactory {
    /// Key-exchange set for servers whose curve25519 exchange NIOSSH cannot
    /// complete — seen with Dropbear on OpenWrt routers, where the shared
    /// secret comes back all-zero (`weakSharedSecret`) although OpenSSH
    /// talks to the same server fine. DH group14 only, plus Citadel's extras
    /// (ssh-rsa host keys, AES128-CTR) for older servers.
    private static let legacyAlgorithms: SSHAlgorithms = {
        var algorithms = SSHAlgorithms.all
        algorithms.keyExchangeAlgorithms = .replace(with: [
            DiffieHellmanGroup14Sha256.self,
            DiffieHellmanGroup14Sha1.self
        ])
        return algorithms
    }()

    /// Connects with the full algorithm set; on a transport/handshake failure
    /// (any NIOSSH error other than a bad auth signature) retries once with
    /// the legacy DH-only key exchange.
    static func connect(
        host: String,
        port: Int,
        authenticationMethod: SSHAuthenticationMethod,
        group: MultiThreadedEventLoopGroup,
        logCategory: LogCategory
    ) async throws -> SSHClient {
        do {
            return try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: authenticationMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all,
                group: group
            )
        } catch let error as NIOSSHError where error.type != .invalidUserAuthSignature {
            logWarning(
                "SSH handshake with \(host):\(port) failed (\(error.type)); retrying with DH group14 key exchange",
                category: logCategory
            )
            return try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: authenticationMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: legacyAlgorithms,
                group: group
            )
        }
    }
}
