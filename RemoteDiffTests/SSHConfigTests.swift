import XCTest
@testable import RemoteDiff

final class SSHConfigTests: XCTestCase {

    func testParseBasicConfig() {
        let config = """
        Host myserver
            HostName 192.168.1.100
            User admin
            Port 2222
            IdentityFile ~/.ssh/id_rsa

        Host devbox
            HostName dev.example.com
            User developer
        """

        let hosts = SSHConfigParser.parse(content: config)
        XCTAssertEqual(hosts.count, 2)

        XCTAssertEqual(hosts[0].name, "myserver")
        XCTAssertEqual(hosts[0].hostname, "192.168.1.100")
        XCTAssertEqual(hosts[0].user, "admin")
        XCTAssertEqual(hosts[0].port, 2222)

        XCTAssertEqual(hosts[1].name, "devbox")
        XCTAssertEqual(hosts[1].hostname, "dev.example.com")
        XCTAssertEqual(hosts[1].user, "developer")
        XCTAssertNil(hosts[1].port)
    }

    func testSkipsWildcardHosts() {
        let config = """
        Host *
            ServerAliveInterval 60

        Host production
            HostName prod.example.com
        """

        let hosts = SSHConfigParser.parse(content: config)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].name, "production")
    }

    func testSkipsComments() {
        let config = """
        # This is a comment
        Host test
            HostName test.example.com
            # Another comment
            User testuser
        """

        let hosts = SSHConfigParser.parse(content: config)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].user, "testuser")
    }

    func testEmptyConfig() {
        let hosts = SSHConfigParser.parse(content: "")
        XCTAssertTrue(hosts.isEmpty)
    }

    func testExpandTilde() {
        let expanded = SSHConfigParser.expandTilde("~/Documents/key")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/Documents/key"))
    }

    // MARK: - Auth options

    func testAuthOptionArgsDisablePasswordForUnlistedHost() {
        XCTAssertEqual(
            SSHService.authOptionArgs(host: "a", allowedHosts: []),
            ["-o", "KbdInteractiveAuthentication=no", "-o", "PasswordAuthentication=no"]
        )
    }

    func testAuthOptionArgsEmptyForAllowedHost() {
        XCTAssertTrue(SSHService.authOptionArgs(host: "a", allowedHosts: ["a"]).isEmpty)
    }

    func testSSHArgumentsPutHostKeyAndAuthOptionsFirst() {
        XCTAssertEqual(
            SSHService.sshArguments(host: "h", extraArgs: ["-o", "ControlPath=/x"], allowedHosts: []),
            ["-o", "StrictHostKeyChecking=yes",
             "-o", "KbdInteractiveAuthentication=no", "-o", "PasswordAuthentication=no",
             "-o", "ControlPath=/x", "--", "h", "bash"]
        )
    }

    func testSSHArgumentsKeepHostKeyCheckingForAllowedHost() {
        XCTAssertEqual(
            SSHService.sshArguments(host: "h", extraArgs: ["-o", "ControlPath=/x"], allowedHosts: ["h"]),
            ["-o", "StrictHostKeyChecking=yes", "-o", "ControlPath=/x", "--", "h", "bash"]
        )
    }

    // MARK: - Host key failures

    private let unknownKey = "No ED25519 host key is known for [127.0.0.1]:2222 and you have requested strict checking.\nHost key verification failed.\n"

    private let changedKey = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
        Offending ED25519 key in /Users/x/.ssh/known_hosts:1
        Host key for [127.0.0.1]:2222 has changed and you have requested strict checking.
        Host key verification failed.
        """

    func testHostKeyFailureHintForUnknownKey() {
        let hint = SSHService.hostKeyFailureHint(stderr: unknownKey, exitCode: 255, host: "pwtest")
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint!.contains("    ssh -o StrictHostKeyChecking=ask pwtest"))
    }

    func testHostKeyFailureHintHandlesCRLF() {
        let crlf = unknownKey.replacingOccurrences(of: "\n", with: "\r\n")
        let hint = SSHService.hostKeyFailureHint(stderr: crlf, exitCode: 255, host: "pwtest")
        XCTAssertTrue(hint?.contains("    ssh -o StrictHostKeyChecking=ask pwtest") ?? false)
    }

    func testHostKeyFailureHintForChangedKey() {
        let hint = SSHService.hostKeyFailureHint(stderr: changedKey, exitCode: 255, host: "pwtest")
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint!.contains("does not match the one saved in known_hosts"))
        XCTAssertFalse(hint!.contains("in Terminal"))
        XCTAssertFalse(hint!.contains("    ssh -o StrictHostKeyChecking=ask pwtest"))
    }

    func testHostKeyFailureHintNilForOtherExitCode() {
        XCTAssertNil(SSHService.hostKeyFailureHint(stderr: unknownKey, exitCode: 1, host: "h"))
    }

    func testHostKeyFailureHintNilForUnrelatedFailure() {
        XCTAssertNil(SSHService.hostKeyFailureHint(stderr: "sam@h: Permission denied (publickey).", exitCode: 255, host: "h"))
    }

    func testHostKeyFailureHintQuotesUnusualHosts() {
        let spaced = SSHService.hostKeyFailureHint(stderr: unknownKey, exitCode: 255, host: "a b")
        XCTAssertTrue(spaced?.contains("    ssh -o StrictHostKeyChecking=ask -- 'a b'") ?? false)
        let option = SSHService.hostKeyFailureHint(stderr: unknownKey, exitCode: 255, host: "-oProxyCommand=x")
        XCTAssertTrue(option?.contains("    ssh -o StrictHostKeyChecking=ask -- '-oProxyCommand=x'") ?? false)
    }

    func testHostKeyFailureHintLeavesUserAtHostBare() {
        let hint = SSHService.hostKeyFailureHint(stderr: unknownKey, exitCode: 255, host: "sam@host.example")
        XCTAssertTrue(hint?.contains("    ssh -o StrictHostKeyChecking=ask sam@host.example") ?? false)
        XCTAssertFalse(hint?.contains("--") ?? true)
    }

    func testHostKeyFailureHintForRevokedKey() {
        let stderr = "@       WARNING: REVOKED HOST KEY DETECTED!               @\nThe ED25519 host key for [127.0.0.1]:2222 is marked as revoked.\nHost key verification failed.\n"
        let hint = SSHService.hostKeyFailureHint(stderr: stderr, exitCode: 255, host: "pwtest")
        XCTAssertTrue(hint?.contains("revoked") ?? false)
        XCTAssertFalse(hint?.contains("in Terminal") ?? true)
    }

    func testMasterArgumentsPutHostKeyAndAuthOptionsFirst() {
        let args = ControlMasterWatcher.masterArguments(host: "h", socketPath: "/s", allowedHosts: [])
        XCTAssertEqual(Array(args.prefix(6)),
                       ["-o", "StrictHostKeyChecking=yes",
                        "-o", "KbdInteractiveAuthentication=no", "-o", "PasswordAuthentication=no"])
        XCTAssertEqual(Array(args.suffix(2)), ["--", "h"])
        XCTAssertTrue(args.contains("ControlPath=/s"))
    }

    func testMasterArgumentsKeepHostKeyCheckingForAllowedHost() {
        let args = ControlMasterWatcher.masterArguments(host: "h", socketPath: "/s", allowedHosts: ["h"])
        XCTAssertEqual(Array(args.prefix(4)), ["-o", "StrictHostKeyChecking=yes", "-o", "ControlMaster=yes"])
    }

    func testAuthFailureHintNilForPublickeyOnly() {
        let stderr = "sam@h: Permission denied (publickey)."
        XCTAssertNil(SSHService.authFailureHint(stderr: stderr, exitCode: 255, host: "h", allowedHosts: []))
    }

    func testAuthFailureHintWhenPasswordOrKeyboardInteractiveOffered() {
        let pw = "sam@h: Permission denied (publickey,password)."
        let kbd = "sam@h: Permission denied (publickey,keyboard-interactive)."
        XCTAssertNotNil(SSHService.authFailureHint(stderr: pw, exitCode: 255, host: "h", allowedHosts: []))
        XCTAssertNotNil(SSHService.authFailureHint(stderr: kbd, exitCode: 255, host: "h", allowedHosts: []))
    }

    func testAuthFailureHintNilForOtherExitCode() {
        let stderr = "sam@h: Permission denied (publickey,password)."
        XCTAssertNil(SSHService.authFailureHint(stderr: stderr, exitCode: 1, host: "h", allowedHosts: []))
    }

    func testAuthFailureHintNilWhenHostAllowedOrUnrelated() {
        let denied = "sam@h: Permission denied (publickey,password)."
        XCTAssertNil(SSHService.authFailureHint(stderr: denied, exitCode: 255, host: "h", allowedHosts: ["h"]))
        XCTAssertNil(SSHService.authFailureHint(stderr: "ssh: connect to host h: Connection refused", exitCode: 255, host: "h", allowedHosts: []))
    }
}
