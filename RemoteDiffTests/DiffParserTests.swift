import XCTest
@testable import RemoteDiff

final class DiffParserTests: XCTestCase {

    // MARK: - Basic Diff

    func testParseSimpleDiff() {
        let raw = """
        diff --git a/hello.swift b/hello.swift
        index abc1234..def5678 100644
        --- a/hello.swift
        +++ b/hello.swift
        @@ -1,5 +1,6 @@
         import Foundation
         
        -func greet() {
        -    print("Hello")
        +func greet(name: String) {
        +    print("Hello, \\(name)")
        +    print("Welcome!")
         }
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 1)

        let file = files[0]
        XCTAssertEqual(file.oldPath, "hello.swift")
        XCTAssertEqual(file.newPath, "hello.swift")
        XCTAssertFalse(file.isBinary)
        XCTAssertEqual(file.hunks.count, 1)

        let hunk = file.hunks[0]
        XCTAssertEqual(hunk.leftStartLine, 1)
        XCTAssertEqual(hunk.rightStartLine, 1)

        // Should have: 1 context, 2 deletions, 3 additions, 1 context = 7 lines
        let additions = hunk.lines.filter { $0.type == .addition }
        let deletions = hunk.lines.filter { $0.type == .deletion }
        XCTAssertEqual(additions.count, 3)
        XCTAssertEqual(deletions.count, 2)
    }

    // MARK: - Multiple Files

    func testParseMultipleFiles() {
        let raw = """
        diff --git a/file1.txt b/file1.txt
        index abc..def 100644
        --- a/file1.txt
        +++ b/file1.txt
        @@ -1,3 +1,3 @@
         line1
        -line2
        +line2-modified
         line3
        diff --git a/file2.txt b/file2.txt
        index abc..def 100644
        --- a/file2.txt
        +++ b/file2.txt
        @@ -1,2 +1,3 @@
         first
        +inserted
         second
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].oldPath, "file1.txt")
        XCTAssertEqual(files[1].oldPath, "file2.txt")
    }

    // MARK: - New File

    func testParseNewFile() {
        let raw = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..abc1234
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,3 @@
        +line1
        +line2
        +line3
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isNewFile)
        XCTAssertEqual(files[0].oldPath, "/dev/null")
        XCTAssertEqual(files[0].newPath, "new.txt")
    }

    // MARK: - Deleted File

    func testParseDeletedFile() {
        let raw = """
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        index abc1234..0000000
        --- a/old.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -goodbye
        -world
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isDeletedFile)
    }

    // MARK: - Binary File

    func testParseBinaryFile() {
        let raw = """
        diff --git a/image.png b/image.png
        index abc..def 100644
        Binary files a/image.png and b/image.png differ
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isBinary)
        XCTAssertTrue(files[0].hunks.isEmpty)
    }

    // MARK: - Multiple Hunks

    func testMultipleHunks() {
        let raw = """
        diff --git a/big.txt b/big.txt
        index abc..def 100644
        --- a/big.txt
        +++ b/big.txt
        @@ -10,3 +10,3 @@
         context
        -old1
        +new1
        @@ -50,3 +50,4 @@
         context
        -old2
        +new2a
        +new2b
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].hunks.count, 2)
        XCTAssertEqual(files[0].hunks[0].leftStartLine, 10)
        XCTAssertEqual(files[0].hunks[1].leftStartLine, 50)
    }

    // MARK: - Hunk Header Parsing

    func testHunkHeaderParsing() {
        XCTAssertEqual(DiffParser.parseHunkHeader("@@ -10,7 +10,8 @@").0, 10)
        XCTAssertEqual(DiffParser.parseHunkHeader("@@ -10,7 +10,8 @@").1, 10)
        XCTAssertEqual(DiffParser.parseHunkHeader("@@ -1 +1 @@").0, 1)
        XCTAssertEqual(DiffParser.parseHunkHeader("@@ -0,0 +1,5 @@").0, 0)
        XCTAssertEqual(DiffParser.parseHunkHeader("@@ -0,0 +1,5 @@").1, 1)
        XCTAssertEqual(DiffParser.parseHunkHeader("@@ -100,20 +105,25 @@ func example()").0, 100)
        XCTAssertEqual(DiffParser.parseHunkHeader("@@ -100,20 +105,25 @@ func example()").1, 105)
    }

    // MARK: - Line Numbers

    func testLineNumberTracking() {
        let raw = """
        diff --git a/test.txt b/test.txt
        index abc..def 100644
        --- a/test.txt
        +++ b/test.txt
        @@ -5,4 +5,5 @@
         context5
        -deleted6
        +added5a
        +added5b
         context7
        """

        let files = DiffParser.parse(raw)
        let lines = files[0].hunks[0].lines

        // context5: left=5
        XCTAssertEqual(lines[0].lineNumber, 5)
        XCTAssertEqual(lines[0].type, .context)

        // deleted6: left=6
        XCTAssertEqual(lines[1].lineNumber, 6)
        XCTAssertEqual(lines[1].type, .deletion)

        // added5a: right=6
        XCTAssertEqual(lines[2].lineNumber, 6)
        XCTAssertEqual(lines[2].type, .addition)

        // added5b: right=7
        XCTAssertEqual(lines[3].lineNumber, 7)
        XCTAssertEqual(lines[3].type, .addition)
    }

    // MARK: - Pair Lines

    func testPairLinesContextOnly() {
        let lines = [
            DiffLine(type: .context, text: "line1", lineNumber: 1),
            DiffLine(type: .context, text: "line2", lineNumber: 2),
        ]
        let pairs = pairLines(lines)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].left?.text, "line1")
        XCTAssertEqual(pairs[0].right?.text, "line1")
    }

    func testPairLinesDeletionAddition() {
        let lines = [
            DiffLine(type: .deletion, text: "old", lineNumber: 1),
            DiffLine(type: .addition, text: "new", lineNumber: 1),
        ]
        let pairs = pairLines(lines)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].left?.text, "old")
        XCTAssertEqual(pairs[0].right?.text, "new")
    }

    func testPairLinesUnevenDeletionsAdditions() {
        let lines = [
            DiffLine(type: .deletion, text: "old1", lineNumber: 1),
            DiffLine(type: .deletion, text: "old2", lineNumber: 2),
            DiffLine(type: .addition, text: "new1", lineNumber: 1),
        ]
        let pairs = pairLines(lines)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].left?.text, "old1")
        XCTAssertEqual(pairs[0].right?.text, "new1")
        XCTAssertEqual(pairs[1].left?.text, "old2")
        XCTAssertEqual(pairs[1].right?.type, .empty)
    }

    func testPairLinesStandaloneAddition() {
        let lines = [
            DiffLine(type: .context, text: "before", lineNumber: 1),
            DiffLine(type: .addition, text: "inserted", lineNumber: 2),
            DiffLine(type: .context, text: "after", lineNumber: 3),
        ]
        let pairs = pairLines(lines)
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs[1].left?.type, .empty)
        XCTAssertEqual(pairs[1].right?.text, "inserted")
    }

    // MARK: - Empty Diff

    func testEmptyDiff() {
        let files = DiffParser.parse("")
        XCTAssertTrue(files.isEmpty)
    }

    func testNonsenseDiff() {
        let files = DiffParser.parse("this is not a diff\njust random text")
        XCTAssertTrue(files.isEmpty)
    }

    // MARK: - Untracked Files (git diff --no-index)

    func testParseUntrackedFileWithContent() {
        let raw = """
        diff --git a/test.py b/test.py
        new file mode 100644
        index 0000000..201be4c
        --- /dev/null
        +++ b/test.py
        @@ -0,0 +1,2 @@
        +print("hello")
        +x = 42
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].newPath, "test.py")
        XCTAssertTrue(files[0].isNewFile)
        XCTAssertFalse(files[0].isBinary)
        XCTAssertEqual(files[0].hunks.count, 1)
        XCTAssertEqual(files[0].hunks[0].lines.count, 2)
        XCTAssertEqual(files[0].hunks[0].lines[0].type, .addition)
        XCTAssertEqual(files[0].hunks[0].lines[0].text, #"print("hello")"#)
        XCTAssertEqual(files[0].hunks[0].lines[1].text, "x = 42")
    }

    func testParseEmptyUntrackedFile() {
        // Empty untracked file: no --- / +++ / hunks, just header
        let raw = """
        diff --git a/empty.py b/empty.py
        new file mode 100644
        index 0000000..e69de29
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].newPath, "empty.py")
        XCTAssertTrue(files[0].isNewFile)
        XCTAssertFalse(files[0].isBinary)
        XCTAssertTrue(files[0].hunks.isEmpty)
    }

    func testParseUntrackedFileMixedWithTracked() {
        // Simulates: git diff HEAD output followed by git diff --no-index output
        let raw = """
        diff --git a/README.md b/README.md
        index 05c167b..3b732f3 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,3 +1,4 @@
         # Title
        +New line
         
         Content
        diff --git a/test.py b/test.py
        new file mode 100644
        index 0000000..201be4c
        --- /dev/null
        +++ b/test.py
        @@ -0,0 +1,2 @@
        +print("hello")
        +x = 42
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 2)

        // First file: tracked modification
        XCTAssertEqual(files[0].displayName, "README.md")
        XCTAssertFalse(files[0].isNewFile)
        XCTAssertEqual(files[0].hunks.count, 1)

        // Second file: untracked new file
        XCTAssertEqual(files[1].displayName, "test.py")
        XCTAssertTrue(files[1].isNewFile)
        XCTAssertEqual(files[1].hunks.count, 1)
        XCTAssertEqual(files[1].hunks[0].lines.count, 2)
    }

    func testParseEmptyUntrackedFileAfterTracked() {
        let raw = """
        diff --git a/README.md b/README.md
        index 05c167b..3b732f3 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,3 +1,3 @@
         # Title
        -Old line
        +New line
         Content
        diff --git a/empty.txt b/empty.txt
        new file mode 100644
        index 0000000..e69de29
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].displayName, "README.md")
        XCTAssertEqual(files[1].displayName, "empty.txt")
        XCTAssertTrue(files[1].isNewFile)
        XCTAssertTrue(files[1].hunks.isEmpty)
    }

    func testParseMultipleUntrackedFiles() {
        let raw = """
        diff --git a/file1.py b/file1.py
        new file mode 100644
        index 0000000..abc1234
        --- /dev/null
        +++ b/file1.py
        @@ -0,0 +1 @@
        +hello
        diff --git a/file2.py b/file2.py
        new file mode 100644
        index 0000000..e69de29
        diff --git a/file3.py b/file3.py
        new file mode 100644
        index 0000000..def5678
        --- /dev/null
        +++ b/file3.py
        @@ -0,0 +1 @@
        +world
        """

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files[0].newPath, "file1.py")
        XCTAssertEqual(files[0].hunks.count, 1)
        XCTAssertEqual(files[1].newPath, "file2.py")
        XCTAssertTrue(files[1].hunks.isEmpty)
        XCTAssertEqual(files[2].newPath, "file3.py")
        XCTAssertEqual(files[2].hunks.count, 1)
    }
}
