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
}
