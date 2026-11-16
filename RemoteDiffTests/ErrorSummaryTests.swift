import XCTest
@testable import RemoteDiff

final class ErrorSummaryTests: XCTestCase {
    private func ssh(_ stderr: String) -> String { ErrorSummary.summarize(stderr: stderr, exitCode: 255) }
    private func remote(_ stderr: String, code: Int32 = 128) -> String { ErrorSummary.summarize(stderr: stderr, exitCode: code) }

    private let banner = (1...40).map { "Banner line \($0): authorised use only" }.joined(separator: "\r\n") + "\r\n"

    // MARK: ssh failures (exit 255)

    func testHostKeyChanged() {
        let stderr = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        Host key verification failed.
        """
        XCTAssertEqual(ssh(stderr), "Host key changed")
    }

    func testHostKeyRevoked() {
        XCTAssertEqual(ssh("@ WARNING: REVOKED HOST KEY DETECTED! @\nHost key verification failed."), "Host key revoked")
    }

    func testHostKeyNotKnownWithCRLF() {
        XCTAssertEqual(ssh("No ED25519 host key is known for h and you have requested strict checking.\r\nHost key verification failed.\r\n"),
                       "Host key not known")
    }

    func testAuthenticationFailedAfterBanner() {
        XCTAssertEqual(ssh(banner + "Permission denied, please try again.\r\ntest@127.0.0.1: Permission denied (publickey,password,keyboard-interactive).\r\n"),
                       "Authentication failed")
    }

    func testTooManyAuthenticationFailures() {
        XCTAssertEqual(ssh("Received disconnect from 127.0.0.1 port 2222:2: Too many authentication failures\r\nDisconnected from 127.0.0.1 port 2222"),
                       "Authentication failed")
    }

    func testHostNotFound() {
        XCTAssertEqual(ssh("ssh: Could not resolve hostname nosuchhost: nodename nor servname provided, or not known\r\n"), "Host not found")
    }

    func testCouldNotConnect() {
        XCTAssertEqual(ssh("ssh: connect to host 10.0.0.1 port 22: Connection refused\r\n"), "Couldn't connect to the host")
        XCTAssertEqual(ssh("ssh: connect to host h port 22: Operation timed out"), "Couldn't connect to the host")
        XCTAssertEqual(ssh("kex_exchange_identification: read: Connection reset by peer\r\nConnection reset by 1.2.3.4 port 22\r\n"),
                       "Couldn't connect to the host")
        XCTAssertEqual(ssh("Connection timed out during banner exchange"), "Couldn't connect to the host")
    }

    func testLostConnection() {
        XCTAssertEqual(ssh("Connection to h closed by remote host.\r\n"), "Lost the connection to the host")
        XCTAssertEqual(ssh("client_loop: send disconnect: Broken pipe\r\n"), "Lost the connection to the host")
        XCTAssertEqual(ssh("mux_client_request_session: read from master failed: Broken pipe"), "Lost the connection to the host")
        XCTAssertEqual(ssh("Control socket connect(/tmp/rdcm/1/m1): No such file or directory\r\n"), "Lost the connection to the host")
    }

    func testUnknownSSHFailure() {
        XCTAssertEqual(ssh(""), "SSH failed")
        XCTAssertEqual(ssh("something unexpected"), "SSH failed")
    }

    // MARK: Spoofing: remote-controlled text must not fake an ssh failure

    func testSSHTextFromRemoteCommandIsNotAnSSHFailure() {
        // A repo's git config or the remote shell can print anything to stderr and exit non-255.
        let fake = "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\nHost key verification failed.\nsam@h: Permission denied (publickey)."
        XCTAssertEqual(remote(fake, code: 1), "Command failed on the host")
    }

    func testBannerMentionOfPermissionDeniedIsNotAuthFailure() {
        // Not ssh's line format (whole line "<who>: Permission denied (<methods>).").
        XCTAssertEqual(ssh("Unauthorised use: Permission denied (see policy) and logged\r\nssh: connect to host h port 22: Connection refused"),
                       "Couldn't connect to the host")
        XCTAssertEqual(ssh("Notice: Host key verification failed. is not something you should see"), "SSH failed")
    }

    func testGitPermissionDeniedIsNotAuthFailure() {
        XCTAssertEqual(remote("error: cannot open .git/FETCH_HEAD: Permission denied"), "Command failed on the host")
    }

    // MARK: Remote command failures (exit != 255)

    func testNotAGitRepository() {
        XCTAssertEqual(remote("fatal: not a git repository (or any of the parent directories): .git"), "Not a git repository")
    }

    func testDubiousOwnership() {
        XCTAssertEqual(remote("fatal: detected dubious ownership in repository at '/src/app'\nTo add an exception..."),
                       "Git doesn't trust the repository's owner (safe.directory)")
    }

    func testGitNotInstalled() {
        XCTAssertEqual(remote("bash: line 1: git: command not found", code: 127), "git isn't installed on the host")
    }

    func testRepositoryFolderNotFound() {
        XCTAssertEqual(remote("bash: line 1: cd: /nope: No such file or directory", code: 1), "Repository folder not found")
    }

    func testGitRefNotFound() {
        XCTAssertEqual(remote("fatal: bad revision 'nope'"), "Git ref not found")
        XCTAssertEqual(remote("fatal: ambiguous argument 'nope': unknown revision or path not in the working tree."), "Git ref not found")
    }

    func testRemoteFallback() {
        XCTAssertEqual(remote("something else broke", code: 2), "Command failed on the host")
        XCTAssertEqual(remote("", code: 3), "Command failed on the host")
    }

    // MARK: Views split the message into summary + details

    func testSummaryIsFirstLineAndDetailsTheRest() {
        let msg = "Authentication failed\n\nhint\n\nstderr\r\n"
        XCTAssertEqual(ErrorMessageView.summary(msg), "Authentication failed")
        XCTAssertEqual(ErrorMessageView.detailText(msg), "hint\n\nstderr")
    }

    func testSingleLineMessageHasNoDetails() {
        XCTAssertEqual(ErrorMessageView.summary("Lost the connection to this host. Click Reconnect to connect again."),
                       "Lost the connection to this host. Click Reconnect to connect again.")
        XCTAssertNil(ErrorMessageView.detailText("No host or repo path configured"))
        XCTAssertEqual(ErrorMessageView.summary(""), "Error")
    }
}
