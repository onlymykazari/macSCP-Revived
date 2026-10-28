//
//  ExternalLaunchRequestTests.swift
//  macSCPTests
//
//  Unit tests for macscp:// URL parsing, the launch queue, and shell quoting
//

import XCTest
@testable import macSCP

final class ExternalLaunchRequestTests: XCTestCase {
    private func parse(_ string: String) -> Result<ExternalLaunchRequest, ExternalLaunchParseError> {
        ExternalLaunchRequest.parse(URL(string: string)!)
    }

    // MARK: - Valid URLs

    func testParse_ConnectionUUID() {
        let id = UUID()
        let result = parse("macscp://open?connection=\(id.uuidString)")
        guard case .success(let request) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertEqual(request.target, .connectionId(id))
        XCTAssertEqual(request.view, .files)
        XCTAssertNil(request.path)
        XCTAssertFalse(request.forceNew)
    }

    func testParse_ConnectionName() {
        let result = parse("macscp://open?connection=Prod%20Web")
        guard case .success(let request) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertEqual(request.target, .connectionName("Prod Web"))
    }

    func testParse_BookmarkName() {
        let result = parse("macscp://open?bookmark=logs&view=terminal&path=/var/log")
        guard case .success(let request) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertEqual(request.target, .bookmarkName("logs"))
        XCTAssertEqual(request.view, .terminal)
        XCTAssertEqual(request.path, "/var/log")
    }

    func testParse_DecodesPathAndQueryValues() {
        let result = parse("macscp://open?connection=web&path=/srv/my%20files")
        guard case .success(let request) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertEqual(request.path, "/srv/my files")
    }

    func testParse_ForceNewVariants() {
        for value in ["1", "true", "yes"] {
            let result = parse("macscp://open?connection=x&new=\(value)")
            guard case .success(let request) = result else {
                return XCTFail("\(result)")
            }
            XCTAssertTrue(request.forceNew, "new=\(value)")
        }
        for value in ["0", "false", ""] {
            let result = parse("macscp://open?connection=x&new=\(value)")
            guard case .success(let request) = result else {
                return XCTFail("\(result)")
            }
            XCTAssertFalse(request.forceNew, "new=\(value)")
        }
    }

    func testParse_MissingHostIsAccepted() {
        let result = parse("macscp://?connection=web")
        guard case .success(let request) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertEqual(request.target, .connectionName("web"))
    }

    func testParse_UnknownParametersIgnored() {
        let result = parse("macscp://open?connection=web&foo=bar&tracker=1")
        guard case .success(let request) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertEqual(request.target, .connectionName("web"))
    }

    func testParse_UserinfoIsIgnored() {
        // Credentials must never be honored — they exist only to be redacted.
        let url = URL(string: "macscp://user:secret@open?connection=web")!
        let result = ExternalLaunchRequest.parse(url)
        guard case .success(let request) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertEqual(request.target, .connectionName("web"))
        XCTAssertFalse(request.sourceURL.contains("secret"))
        XCTAssertTrue(request.sourceURL.contains("***"))
    }

    // MARK: - Invalid URLs

    func testParse_BadScheme() {
        guard case .failure(.badScheme) = parse("winscp://open?connection=x") else {
            return XCTFail("expected badScheme")
        }
    }

    func testParse_BadHost() {
        guard case .failure(.badHost) = parse("macscp://session?connection=x") else {
            return XCTFail("expected badHost")
        }
    }

    func testParse_MissingTarget() {
        guard case .failure(.missingTarget) = parse("macscp://open") else {
            return XCTFail("expected missingTarget")
        }
        guard case .failure(.missingTarget) = parse("macscp://open?view=terminal&path=/tmp") else {
            return XCTFail("expected missingTarget for empty connection value")
        }
    }

    func testParse_BothTargets() {
        guard case .failure(.bothTargets) = parse("macscp://open?connection=x&bookmark=y") else {
            return XCTFail("expected bothTargets")
        }
    }

    func testParse_BadView() {
        guard case .failure(.badView) = parse("macscp://open?connection=x&view=explorer") else {
            return XCTFail("expected badView")
        }
    }

    // MARK: - Shell quoting

    func testTerminalCDCommand_SimplePath() {
        XCTAssertEqual(ExternalLaunchSupport.terminalCDCommand(path: "/var/log"), "cd -- '/var/log'\n")
    }

    func testTerminalCDCommand_EscapesSingleQuotes() {
        XCTAssertEqual(
            ExternalLaunchSupport.terminalCDCommand(path: "/srv/it's here"),
            "cd -- '/srv/it'\\''s here'\n"
        )
    }

    func testTerminalCDCommand_ExpandsTilde() {
        XCTAssertEqual(ExternalLaunchSupport.terminalCDCommand(path: "~"), "cd -- \"${HOME}\"\n")
        XCTAssertEqual(
            ExternalLaunchSupport.terminalCDCommand(path: "~/logs"),
            "cd -- \"${HOME}\"'/logs'\n"
        )
        XCTAssertEqual(
            ExternalLaunchSupport.terminalCDCommand(path: "~/it's here"),
            "cd -- \"${HOME}\"'/it'\\''s here'\n"
        )
        // A mid-path ~ is a literal character and stays quoted.
        XCTAssertEqual(
            ExternalLaunchSupport.terminalCDCommand(path: "/srv/~backup"),
            "cd -- '/srv/~backup'\n"
        )
    }

    func testTerminalCDCommand_RejectsControlCharacters() {
        XCTAssertNil(ExternalLaunchSupport.terminalCDCommand(path: "/x'; rm -rf ~;\n'"))
        XCTAssertNil(ExternalLaunchSupport.terminalCDCommand(path: "/a\u{1B}[31m"))
        XCTAssertNil(ExternalLaunchSupport.terminalCDCommand(path: ""))
        XCTAssertNil(ExternalLaunchSupport.terminalCDCommand(path: "   "))
    }

    func testMakeURL_RoundTrips() {
        let url = ExternalLaunchSupport.makeURL(
            connection: "My Server", view: .terminal, path: "/srv/a b", forceNew: true
        )
        XCTAssertNotNil(url)
        guard case .success(let request) = ExternalLaunchRequest.parse(url!) else {
            return XCTFail("generated URL should parse")
        }
        XCTAssertEqual(request.target, .connectionName("My Server"))
        XCTAssertEqual(request.view, .terminal)
        XCTAssertEqual(request.path, "/srv/a b")
        XCTAssertTrue(request.forceNew)
    }

    // MARK: - Queue

    @MainActor
    func testQueue_EnqueueDrainOrderAndClearing() {
        // Start from a known-empty state.
        ExternalLaunchQueue.shared.drain()
        let good = URL(string: "macscp://open?connection=web")!
        let bad = URL(string: "macscp://open?view=terminal")!

        ExternalLaunchQueue.shared.enqueue(bad)
        ExternalLaunchQueue.shared.enqueue(good)

        let outcomes = ExternalLaunchQueue.shared.drain()
        XCTAssertEqual(outcomes.count, 2)
        guard case .rejected = outcomes[0] else {
            return XCTFail("expected rejected first")
        }
        guard case .request(let request) = outcomes[1] else {
            return XCTFail("expected request second")
        }
        XCTAssertEqual(request.target, .connectionName("web"))

        // Draining clears the queue.
        XCTAssertTrue(ExternalLaunchQueue.shared.drain().isEmpty)
    }
}
