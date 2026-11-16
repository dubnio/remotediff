import XCTest
@testable import RemoteDiff

final class SSHServiceTests: XCTestCase {

    // MARK: - shellQuote

    func testShellQuotePlain() {
        XCTAssertEqual(SSHService.shellQuote("abc"), "'abc'")
    }

    func testShellQuoteEmbeddedSingleQuote() {
        XCTAssertEqual(SSHService.shellQuote("a'b"), "'a'\\''b'")
    }

    func testShellQuoteEmpty() {
        XCTAssertEqual(SSHService.shellQuote(""), "''")
    }

    // MARK: - shellQuotePath

    func testShellQuotePathBareTilde() {
        XCTAssertEqual(SSHService.shellQuotePath("~"), "~")
    }

    func testShellQuotePathTildeSlash() {
        XCTAssertEqual(SSHService.shellQuotePath("~/a b"), "~/'a b'")
    }

    func testShellQuotePathEmbeddedQuote() {
        XCTAssertEqual(SSHService.shellQuotePath("/x'y"), "'/x'\\''y'")
    }

    // MARK: - Script builders

    func testDiffScriptQuotesInjectedPath() {
        let script = SSHService.buildDiffScript(repoPath: "/tmp/x; rm -rf /", gitRef: "HEAD",
                                                includeStaged: false, includeUntracked: false)
        XCTAssertEqual(script, "cd -- '/tmp/x; rm -rf /' && git diff 'HEAD' --")
    }

    func testDiffScriptEmptyRefHasNoArgument() {
        let script = SSHService.buildDiffScript(repoPath: "/r", gitRef: "",
                                                includeStaged: false, includeUntracked: false)
        XCTAssertEqual(script, "cd -- '/r' && git diff --")
    }

    // Also checks that the untracked-files loop is suppressed for ranges.
    func testDiffScriptRange() {
        let script = SSHService.buildDiffScript(repoPath: "/r", gitRef: "main..feature",
                                                includeStaged: true, includeUntracked: true)
        XCTAssertEqual(script, "cd -- '/r' && git diff 'main..feature' --")
    }

    func testDiffScriptUntrackedSuffix() {
        let script = SSHService.buildDiffScript(repoPath: "/r", gitRef: "HEAD",
                                                includeStaged: false, includeUntracked: true)
        XCTAssertEqual(script, "cd -- '/r' && git diff 'HEAD' --\n" + #"git ls-files --others --exclude-standard | while IFS= read -r f; do git diff --no-index -- /dev/null "$f" 2>/dev/null || true; done"#)
    }

    func testPollScriptQuotes() {
        let script = SSHService.buildPollScript(repoPath: "~/a'b", gitRef: "HEAD~1",
                                                includeStaged: false, includeUntracked: true)
        XCTAssertEqual(script, "cd -- ~/'a'\\''b' && git diff --stat 'HEAD~1' --\necho ---untracked---\ngit ls-files --others --exclude-standard")
    }

    func testBranchScriptQuotesInjectedPath() {
        XCTAssertEqual(SSHService.buildBranchScript(repoPath: "/tmp/x; id"),
                       "cd -- '/tmp/x; id' && git rev-parse --abbrev-ref HEAD")
    }

    func testBranchScriptTildeUserWithSpace() {
        XCTAssertEqual(SSHService.buildBranchScript(repoPath: "~bob/my repo"),
                       "cd -- ~bob/'my repo' && git rev-parse --abbrev-ref HEAD")
    }

    // MARK: - File content script

    func testFileContentScriptNewPathWithQuote() {
        let script = SSHService.buildFileContentScript(repoPath: "/r", gitRef: "HEAD", newPath: "a'b", oldPath: nil)
        XCTAssertEqual(script, "cd -- '/r' && cat -- 'a'\\''b'")
    }

    func testFileContentScriptNewPathCommandSubstitution() {
        let script = SSHService.buildFileContentScript(repoPath: "/r", gitRef: "HEAD", newPath: "$(id)", oldPath: nil)
        XCTAssertEqual(script, "cd -- '/r' && cat -- '$(id)'")
    }

    func testFileContentScriptNewPathWithNewline() {
        let script = SSHService.buildFileContentScript(repoPath: "/r", gitRef: "HEAD", newPath: "a\nb", oldPath: nil)
        XCTAssertEqual(script, "cd -- '/r' && cat -- 'a\nb'")
    }

    func testFileContentScriptNewPathDash() {
        let script = SSHService.buildFileContentScript(repoPath: "/r", gitRef: "HEAD", newPath: "-n", oldPath: nil)
        XCTAssertEqual(script, "cd -- '/r' && cat -- '-n'")
    }

    func testFileContentScriptOldPathRefConcatenation() {
        let script = SSHService.buildFileContentScript(repoPath: "/r", gitRef: "main", newPath: "new", oldPath: "o'ld")
        XCTAssertEqual(script, "cd -- '/r' && cat -- 'new'\necho '<<<REMOTEDIFF_SEPARATOR>>>'\ngit show 'main:o'\\''ld' 2>/dev/null || echo ''")
    }

    func testFileContentScriptEmptyRefDefaultsToHead() {
        let script = SSHService.buildFileContentScript(repoPath: "/r", gitRef: "", newPath: "n", oldPath: "o")
        XCTAssertTrue(script.contains("git show 'HEAD:o'"))
    }

    func testShellQuotePathTildeUser() {
        XCTAssertEqual(SSHService.shellQuotePath("~bob"), "~bob")
        XCTAssertEqual(SSHService.shellQuotePath("~bob/a b"), "~bob/'a b'")
        XCTAssertEqual(SSHService.shellQuotePath("~/x"), "~/'x'")
    }
}
