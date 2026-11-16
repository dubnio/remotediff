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
             "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
             "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes",
             "-o", "ControlPath=/x", "--", "h", "bash"]
        )
    }

    func testSSHArgumentsKeepHostKeyCheckingForAllowedHost() {
        XCTAssertEqual(
            SSHService.sshArguments(host: "h", extraArgs: ["-o", "ControlPath=/x"], allowedHosts: ["h"]),
            ["-o", "StrictHostKeyChecking=yes",
             "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
             "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes",
             "-o", "ControlPath=/x", "--", "h", "bash"]
        )
    }

    func testClientArgumentsUseExistingSocketOnly() {
        let args = SSHConnectionManager.clientArguments(socketPath: "/s")
        XCTAssertEqual(Array(args.prefix(2)), ["-o", "ControlPath=/s"])
        for option in ["ControlMaster=no", "BatchMode=yes", "IdentityAgent=none", "PubkeyAuthentication=no",
                       "PasswordAuthentication=no", "KbdInteractiveAuthentication=no",
                       "GSSAPIAuthentication=no", "HostbasedAuthentication=no"] {
            XCTAssertTrue(args.contains(option), option)
        }
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
        let args = SSHConnectionManager.masterArguments(host: "h", socketPath: "/s", allowedHosts: [])
        XCTAssertEqual(Array(args.prefix(6)),
                       ["-o", "StrictHostKeyChecking=yes",
                        "-o", "KbdInteractiveAuthentication=no", "-o", "PasswordAuthentication=no"])
        XCTAssertEqual(Array(args.suffix(2)), ["--", "h"])
        XCTAssertTrue(args.contains("ControlMaster=yes"))
        XCTAssertTrue(args.contains("ControlPath=/s"))
        XCTAssertTrue(args.contains("ControlPersist=no"))
        XCTAssertTrue(args.contains("NumberOfPasswordPrompts=1"))
        XCTAssertTrue(args.contains("ForkAfterAuthentication=no"))
        XCTAssertTrue(args.contains("RemoteCommand=none"))
        XCTAssertTrue(args.contains("-N"))
        XCTAssertTrue(args.contains("ConnectTimeout=10"))
        for option in ["ForwardAgent=no", "ForwardX11=no", "ClearAllForwardings=yes"] {
            XCTAssertTrue(args.contains(option), option)
        }
    }

    func testMasterArgumentsKeepHostKeyCheckingForAllowedHost() {
        let args = SSHConnectionManager.masterArguments(host: "h", socketPath: "/s", allowedHosts: ["h"])
        XCTAssertEqual(Array(args.prefix(2)), ["-o", "StrictHostKeyChecking=yes"])
        XCTAssertFalse(args.contains("PasswordAuthentication=no"))
        XCTAssertFalse(args.contains("KbdInteractiveAuthentication=no"))
    }

    // MARK: - Socket path

    func testSocketPathsAreUniqueAcrossCalls() {
        let manager = SSHConnectionManager()
        XCTAssertNotEqual(manager.nextSocketPath(), manager.nextSocketPath())
    }

    func testSocketPathIsInsidePerPidDirectoryAndShort() {
        let manager = SSHConnectionManager()
        let path = manager.nextSocketPath()
        XCTAssertEqual(URL(fileURLWithPath: path).deletingLastPathComponent().path,
                       URL(fileURLWithPath: SSHConnectionManager.socketDirectory).path)
        XCTAssertTrue(SSHConnectionManager.socketDirectory.hasSuffix("/" + String(getpid())))
        XCTAssertLessThan(path.utf8.count + 17, 104)
    }

    // MARK: - Failure memo, client args, stash

    func testShouldFailFast() {
        let now: TimeInterval = 100
        XCTAssertFalse(SSHConnectionManager.shouldFailFast(requestedAt: now, lastFailureAt: nil))
        XCTAssertTrue(SSHConnectionManager.shouldFailFast(requestedAt: now, lastFailureAt: now + 1))
        XCTAssertFalse(SSHConnectionManager.shouldFailFast(requestedAt: now + 1, lastFailureAt: now))
    }

    func testClientArgumentsDisableProxyAndAuth() {
        let args = SSHConnectionManager.clientArguments(socketPath: "/s")
        XCTAssertTrue(args.contains("ProxyCommand=false"))
        XCTAssertTrue(args.contains("SessionType=default"))
        XCTAssertTrue(args.contains("ForkAfterAuthentication=no"))
        XCTAssertTrue(args.contains("ProxyJump=none"))
        XCTAssertTrue(args.contains("BatchMode=yes"))
    }

    func testFailureMessageIsSummaryThenHintsThenStderr() {
        let msg = SSHService.failureMessage(stderr: unknownKey, exitCode: 255, host: "pwtest", allowedHosts: [])
        XCTAssertTrue(msg.hasPrefix("Host key not known: see Details\n\n"))
        XCTAssertTrue(msg.hasSuffix("\n\n" + unknownKey))
        XCTAssertLessThan(msg.range(of: "StrictHostKeyChecking=ask pwtest")!.lowerBound, msg.range(of: unknownKey)!.lowerBound)
    }

    func testFailureMessageNamesPasswordSettingInSummary() {
        let msg = SSHService.failureMessage(stderr: "test@h: Permission denied (publickey,password).", exitCode: 255, host: "h", allowedHosts: [])
        XCTAssertTrue(msg.hasPrefix("Authentication failed: password login is off for this host\n\n"))
        XCTAssertTrue(msg.contains("Allow password authentication for this host"))
    }

    func testFailureMessageWithoutHints() {
        XCTAssertEqual(SSHService.failureMessage(stderr: "boom\n", exitCode: 1, host: "h", allowedHosts: []),
                       "Command failed on the host\n\nboom\n")
        XCTAssertEqual(SSHService.failureMessage(stderr: "", exitCode: 3, host: "h", allowedHosts: []),
                       "Command failed on the host\n\nSSH exited with code 3")
    }

    func testChangedKeyHintPointsBelow() {
        let hint = SSHService.hostKeyFailureHint(stderr: changedKey, exitCode: 255, host: "pwtest")
        XCTAssertTrue(hint?.contains("below") ?? false)
        XCTAssertFalse(hint?.contains("above") ?? true)
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
