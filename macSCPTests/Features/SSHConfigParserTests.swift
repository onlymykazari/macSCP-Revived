//
//  SSHConfigParserTests.swift
//  macSCPTests
//
//  Unit tests for SSHConfigParser
//

import XCTest
@testable import macSCP

final class SSHConfigParserTests: XCTestCase {

    func testParseBasic() {
        let config = """
        Host prod-web
            HostName web.example.com
            User deploy
            Port 2222
            IdentityFile ~/.ssh/id_ed25519
        """

        let hosts = SSHConfigParser.parse(config)

        XCTAssertEqual(hosts.count, 1)
        let host = try! XCTUnwrap(hosts.first)
        XCTAssertEqual(host.name, "prod-web")
        XCTAssertEqual(host.host, "web.example.com")
        XCTAssertEqual(host.user, "deploy")
        XCTAssertEqual(host.port, 2222)
        XCTAssertEqual(host.identityFile, FileManager.realHomeDirectory + "/.ssh/id_ed25519")
        XCTAssertEqual(host.authMethod, .privateKey)
    }

    func testParseMinimalHostFallsBackToAlias() {
        let hosts = SSHConfigParser.parse("Host server1\n    Port 2200")

        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts.first?.name, "server1")
        XCTAssertEqual(hosts.first?.host, "server1")
        XCTAssertEqual(hosts.first?.port, 2200)
        XCTAssertEqual(hosts.first?.user, nil)
        XCTAssertEqual(hosts.first?.authMethod, .password)
    }

    func testParseEqualsForm() {
        let hosts = SSHConfigParser.parse("Host=box\nHostName=box.internal\nUser=root\nPort=22022")

        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts.first?.host, "box.internal")
        XCTAssertEqual(hosts.first?.user, "root")
        XCTAssertEqual(hosts.first?.port, 22022)
    }

    func testKeywordsAreCaseInsensitive() {
        let hosts = SSHConfigParser.parse("host box\nhostname 10.0.0.1\nUSER admin\nport 22\nIDENTITYFILE /tmp/k")

        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts.first?.host, "10.0.0.1")
        XCTAssertEqual(hosts.first?.user, "admin")
        XCTAssertEqual(hosts.first?.identityFile, "/tmp/k")
    }

    func testCommentsAndBlankLinesIgnored() {
        let config = """
        # Global comment
        Host box

            # inner comment
            HostName box.local # trailing comment
        """

        let hosts = SSHConfigParser.parse(config)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts.first?.host, "box.local")
    }

    func testWildcardPatternsSkipped() {
        let config = """
        Host *
            ForwardAgent yes

        Host bastion
            HostName bastion.example.com
        """

        let hosts = SSHConfigParser.parse(config)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts.first?.name, "bastion")
    }

    func testMixedPatternsImportOnlyConcrete() {
        let hosts = SSHConfigParser.parse("Host web *.example.com ?frag\n    HostName web.internal")

        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts.first?.name, "web")
        XCTAssertEqual(hosts.first?.host, "web.internal")
    }

    func testDuplicateAliasFirstValueWins() {
        let config = """
        Host box
            HostName first.example.com
            User first

        Host box
            HostName second.example.com
            User second
            Port 2222
        """

        let hosts = SSHConfigParser.parse(config)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts.first?.host, "first.example.com")
        XCTAssertEqual(hosts.first?.user, "first")
        XCTAssertEqual(hosts.first?.port, 22)
    }

    func testIdentityFileTakesFirstAndExpandsTilde() {
        let config = """
        Host box
            IdentityFile ~/.ssh/id_rsa
            IdentityFile ~/.ssh/id_ed25519
        """

        let hosts = SSHConfigParser.parse(config)
        XCTAssertEqual(hosts.first?.identityFile, FileManager.realHomeDirectory + "/.ssh/id_rsa")
    }

    func testQuotedIdentityFileWithSpaces() {
        let hosts = SSHConfigParser.parse("Host box\n    IdentityFile \"/Users/me/My Keys/work_key\"")

        XCTAssertEqual(hosts.first?.identityFile, "/Users/me/My Keys/work_key")
    }

    func testInvalidPortFallsBackToDefault() {
        let hosts = SSHConfigParser.parse("Host box\n    Port not-a-number\n    HostName h")

        XCTAssertEqual(hosts.first?.port, 22)
    }

    func testEmptyAndGarbageInput() {
        XCTAssertTrue(SSHConfigParser.parse("").isEmpty)
        XCTAssertTrue(SSHConfigParser.parse("# only a comment").isEmpty)
        XCTAssertTrue(SSHConfigParser.parse("ForwardAgent yes\nCompression no").isEmpty)
    }

    func testMultipleHostsInOrder() {
        let config = """
        Host a
            HostName a.example.com

        Host b
            HostName b.example.com
            Port 2222
        """

        let hosts = SSHConfigParser.parse(config)
        XCTAssertEqual(hosts.map(\.name), ["a", "b"])
        XCTAssertEqual(hosts.last?.port, 2222)
    }

    func testSuggestedUsernameFallsBackToLocalUser() {
        let hosts = SSHConfigParser.parse("Host box\n    HostName h")
        XCTAssertEqual(hosts.first?.suggestedUsername, NSUserName())
    }
}
