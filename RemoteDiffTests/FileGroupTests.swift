import XCTest
@testable import RemoteDiff

final class FileGroupTests: XCTestCase {

    private func makeFile(_ path: String) -> FileDiff {
        FileDiff(oldPath: path, newPath: path, isBinary: false, hunks: [])
    }

    func testGroupsFilesByDirectory() {
        let files = [
            makeFile("app/adapters/delta_api.py"),
            makeFile("app/adapters/dentaquest_api.py"),
            makeFile("app/core/models.py"),
            makeFile("app/core/tasks.py"),
            makeFile("app/core/tests/test_admin.py"),
        ]
        let groups = FileGroup.group(files)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].directory, "app/adapters")
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[1].directory, "app/core")
        XCTAssertEqual(groups[1].files.count, 2)
        XCTAssertEqual(groups[2].directory, "app/core/tests")
        XCTAssertEqual(groups[2].files.count, 1)
    }

    func testPreservesFirstAppearanceOrder() {
        // Even if a directory reappears, it stays in its original position.
        let files = [
            makeFile("app/core/models.py"),
            makeFile("app/adapters/x.py"),
            makeFile("app/core/tasks.py"),  // back to app/core after adapters
        ]
        let groups = FileGroup.group(files)
        XCTAssertEqual(groups.map { $0.directory }, ["app/core", "app/adapters"])
        XCTAssertEqual(groups[0].files.map { $0.displayName },
                       ["app/core/models.py", "app/core/tasks.py"])
    }

    func testRootFilesUseEmptyDirectory() {
        let files = [makeFile("README.md"), makeFile("Makefile")]
        let groups = FileGroup.group(files)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].directory, "")
        XCTAssertEqual(groups[0].displayDirectory, "/")
    }

    func testDisplayDirectoryUsesBreadcrumbSeparator() {
        let group = FileGroup(directory: "app/core/tests", files: [])
        XCTAssertEqual(group.displayDirectory, "app › core › tests")
    }

    func testEmptyInputProducesNoGroups() {
        XCTAssertTrue(FileGroup.group([]).isEmpty)
    }

    func testMixedRootAndNestedFiles() {
        let files = [
            makeFile("README.md"),
            makeFile("app/core/models.py"),
            makeFile("Makefile"),
        ]
        let groups = FileGroup.group(files)
        XCTAssertEqual(groups.map { $0.directory }, ["", "app/core"])
        XCTAssertEqual(groups[0].files.map { $0.displayName }, ["README.md", "Makefile"])
        XCTAssertEqual(groups[1].files.map { $0.displayName }, ["app/core/models.py"])
    }
}
