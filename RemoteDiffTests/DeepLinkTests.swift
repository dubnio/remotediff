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
}
