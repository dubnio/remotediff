import XCTest
@testable import RemoteDiff

final class DeepLinkTests: XCTestCase {

    // MARK: - Basic Parsing

    func testBasicDeepLink() {
        let url = URL(string: "remotediff://open?host=mac-studio&path=Development/myapp/api")!
        let link = DeepLink.parse(from: url)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.host, "mac-studio")
        XCTAssertEqual(link?.repoPath, "Development/myapp/api")
        XCTAssertEqual(link?.gitRef, "HEAD")  // default
        XCTAssertFalse(link!.includeStaged)
        XCTAssertFalse(link!.includeUntracked)
    }

    func testDeepLinkWithAllOptions() {
        let url = URL(string: "remotediff://open?host=prod-server&path=%7E/apps/api&ref=main&staged=1&untracked=1")!
        let link = DeepLink.parse(from: url)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.host, "prod-server")
        XCTAssertEqual(link?.repoPath, "~/apps/api")
        XCTAssertEqual(link?.gitRef, "main")
        XCTAssertTrue(link!.includeStaged)
        XCTAssertTrue(link!.includeUntracked)
    }

    func testDeepLinkWithCustomRef() {
        let url = URL(string: "remotediff://open?host=dev&path=project&ref=HEAD~5")!
        let link = DeepLink.parse(from: url)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.gitRef, "HEAD~5")
    }

    func testDeepLinkWithRefRange() {
        let url = URL(string: "remotediff://open?host=dev&path=project&ref=main..feature")!
        let link = DeepLink.parse(from: url)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.gitRef, "main..feature")
    }

    // MARK: - Invalid URLs

    func testWrongSchemeReturnsNil() {
        let url = URL(string: "https://open?host=mac-studio&path=foo")!
        XCTAssertNil(DeepLink.parse(from: url))
    }

    func testMissingHostReturnsNil() {
        let url = URL(string: "remotediff://open?path=foo")!
        XCTAssertNil(DeepLink.parse(from: url))
    }

    func testEmptyHostReturnsNil() {
        let url = URL(string: "remotediff://open?host=&path=foo")!
        XCTAssertNil(DeepLink.parse(from: url))
    }

    func testMissingPathReturnsNil() {
        let url = URL(string: "remotediff://open?host=mac-studio")!
        XCTAssertNil(DeepLink.parse(from: url))
    }

    func testEmptyPathReturnsNil() {
        let url = URL(string: "remotediff://open?host=mac-studio&path=")!
        XCTAssertNil(DeepLink.parse(from: url))
    }

    // MARK: - User@Host Format

    func testUserAtHost() {
        let url = URL(string: "remotediff://open?host=ernesto%40mac-studio&path=Development/myapp/api")!
        let link = DeepLink.parse(from: url)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.host, "ernesto@mac-studio")
        XCTAssertEqual(link?.repoPath, "Development/myapp/api")
    }

    func testUserAtHostWithAllOptions() {
        let url = URL(string: "remotediff://open?host=deploy%40prod-server&path=%7E/apps/api&ref=main&staged=1&untracked=1")!
        let link = DeepLink.parse(from: url)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.host, "deploy@prod-server")
        XCTAssertEqual(link?.repoPath, "~/apps/api")
        XCTAssertEqual(link?.gitRef, "main")
        XCTAssertTrue(link!.includeStaged)
        XCTAssertTrue(link!.includeUntracked)
    }

    // MARK: - Edge Cases

    func testPathWithSpaces() {
        let url = URL(string: "remotediff://open?host=dev&path=my%20project/src")!
        let link = DeepLink.parse(from: url)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.repoPath, "my project/src")
    }

    func testStagedWithoutUntracked() {
        let url = URL(string: "remotediff://open?host=dev&path=project&staged=1&untracked=0")!
        let link = DeepLink.parse(from: url)

        XCTAssertTrue(link!.includeStaged)
        XCTAssertFalse(link!.includeUntracked)
    }

    // MARK: - Validation (injection hardening)

    private func parse(_ query: String) -> DeepLink? {
        DeepLink.parse(from: URL(string: "remotediff://open?\(query)")!)
    }

    func testRejectsHostStartingWithDash() {
        XCTAssertNil(parse("host=-v&path=foo"))
    }

    func testRejectsRefWithShellMetacharacters() {
        XCTAssertNil(parse("host=dev&path=p&ref=main;id"))
        XCTAssertNil(parse("host=dev&path=p&ref=main%20x"))
        XCTAssertNil(parse("host=dev&path=p&ref=%24(id)"))
        XCTAssertNil(parse("host=dev&path=p&ref=%60id%60"))
        XCTAssertNil(parse("host=dev&path=p&ref=a%7Cb"))
    }

    func testRejectsRefStartingWithDash() {
        XCTAssertNil(parse("host=dev&path=p&ref=-p"))
        XCTAssertNil(parse("host=dev&path=p&ref=--cached"))
    }

    func testRejectsRefWithTwoRanges() {
        XCTAssertNil(parse("host=dev&path=p&ref=a..b..c"))
    }

    func testAcceptsValidRefs() {
        for ref in ["main..feature", "HEAD~5", "v1.2.3", "release/2024", "HEAD%5E", "feature+x"] {
            XCTAssertNotNil(parse("host=dev&path=p&ref=\(ref)"), ref)
        }
        XCTAssertEqual(parse("host=dev&path=p&ref=HEAD%5E")?.gitRef, "HEAD^")
    }

    func testRejectsPathWithNewline() {
        XCTAssertNil(parse("host=dev&path=a%0Ab"))
        XCTAssertNil(parse("host=dev&path=a%0Db"))
    }

    func testAcceptsPathWithShellCharacters() {
        // Quoting at every sink handles these
        let link = parse("host=dev&path=my%20dir/$x;%27y%22")
        XCTAssertEqual(link?.repoPath, "my dir/$x;'y\"")
    }

    func testAcceptsUserAtHost() {
        XCTAssertEqual(parse("host=user%40host&path=p")?.host, "user@host")
    }

    func testAcceptsPathStartingWithDash() {
        // Every sink uses `cd --`, so a leading dash is just a relative directory name
        XCTAssertEqual(parse("host=dev&path=-relative/path")?.repoPath, "-relative/path")
    }

    func testRejectsPathWithUnicodeSeparatorsAndControls() {
        XCTAssertNil(parse("host=dev&path=a%E2%80%A8b"))  // U+2028
        XCTAssertNil(parse("host=dev&path=a%E2%80%AEb"))  // U+202E RTL override
        XCTAssertNil(parse("host=dev&path=a%09b"))        // tab
    }

    func testRejectsMalformedHosts() {
        for host in ["a%3Bid", "a%25h", "a/b", "a%20b", "user%40", "%40host"] {
            XCTAssertNil(parse("host=\(host)&path=p"), host)
        }
    }

    func testRejectsPathWithNul() {
        XCTAssertNil(parse("host=dev&path=a%00b"))
    }

    func testAcceptsReflogAndUpstreamRefs() {
        XCTAssertEqual(parse("host=dev&path=p&ref=HEAD%40%7B1%7D")?.gitRef, "HEAD@{1}")
        XCTAssertEqual(parse("host=dev&path=p&ref=%40%7Bu%7D")?.gitRef, "@{u}")
    }

    func testAcceptsEncodedUserAtHostAndIPv6() {
        XCTAssertEqual(parse("host=user%40host.example&path=p")?.host, "user@host.example")
        XCTAssertEqual(parse("host=fe80::1&path=p")?.host, "fe80::1")
    }
}
