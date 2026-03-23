import XCTest
@testable import RemoteDiff

final class DisplayLineBuilderTests: XCTestCase {

    // MARK: - Diff Mode (left side)

    func testDiffLeftSide_contextLine() {
        let hunk = DiffHunk(header: "@@ -1,3 +1,3 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context, text: "hello", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "test.swift", newPath: "test.swift", isBinary: false, hunks: [hunk])

        let lines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)

        // Should have hunk header + 1 content line
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].isHunkHeader)
        XCTAssertEqual(lines[1].lineNumber, 1)
        XCTAssertEqual(lines[1].text, "hello")
        XCTAssertEqual(lines[1].type, .context)
    }

    func testDiffLeftSide_deletionShows() {
        let hunk = DiffHunk(header: "@@ -1,2 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "old line", lineNumber: 1),
            DiffLine(type: .addition, text: "new line", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "test.swift", newPath: "test.swift", isBinary: false, hunks: [hunk])

        let lines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)
        let contentLines = lines.filter { !$0.isHunkHeader }

        // Left side should show deletion
        XCTAssertEqual(contentLines.count, 1)
        XCTAssertEqual(contentLines[0].type, .deletion)
        XCTAssertEqual(contentLines[0].text, "old line")
    }

    func testDiffRightSide_additionShows() {
        let hunk = DiffHunk(header: "@@ -1,2 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "old line", lineNumber: 1),
            DiffLine(type: .addition, text: "new line", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "test.swift", newPath: "test.swift", isBinary: false, hunks: [hunk])

        let lines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .right)
        let contentLines = lines.filter { !$0.isHunkHeader }

        XCTAssertEqual(contentLines.count, 1)
        XCTAssertEqual(contentLines[0].type, .addition)
        XCTAssertEqual(contentLines[0].text, "new line")
    }

    func testDiffEmptyPadding() {
        let hunk = DiffHunk(header: "@@ -1,2 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "line1", lineNumber: 1),
            DiffLine(type: .deletion, text: "line2", lineNumber: 2),
            DiffLine(type: .addition, text: "combined", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let leftLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)
        let rightLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .right)

        let leftContent = leftLines.filter { !$0.isHunkHeader }
        let rightContent = rightLines.filter { !$0.isHunkHeader }

        // Both sides should have same count (padded)
        XCTAssertEqual(leftContent.count, rightContent.count)
        // Left: 2 deletions, Right: 1 addition + 1 empty
        XCTAssertEqual(leftContent[0].type, .deletion)
        XCTAssertEqual(leftContent[1].type, .deletion)
        XCTAssertEqual(rightContent[0].type, .addition)
        XCTAssertEqual(rightContent[1].type, .empty)
    }

    func testDiffHunkHeader() {
        let hunk = DiffHunk(header: "@@ -10,3 +12,5 @@ func example()", leftStartLine: 10, rightStartLine: 12, lines: [
            DiffLine(type: .context, text: "code", lineNumber: 10),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let lines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)

        XCTAssertTrue(lines[0].isHunkHeader)
        XCTAssertTrue(lines[0].text.contains("func example()"))
        XCTAssertNil(lines[0].lineNumber)
    }

    func testDiffMultipleHunks() {
        let hunk1 = DiffHunk(header: "@@ -1,1 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context, text: "a", lineNumber: 1),
        ])
        let hunk2 = DiffHunk(header: "@@ -10,1 +10,1 @@", leftStartLine: 10, rightStartLine: 10, lines: [
            DiffLine(type: .context, text: "b", lineNumber: 10),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk1, hunk2])

        let lines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)
        let headers = lines.filter { $0.isHunkHeader }

        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(lines.count, 4) // 2 headers + 2 content
    }

    // MARK: - Full File Mode

    func testFullFileLines() {
        let content = "line one\nline two\nline three"
        let changedLines: Set<Int> = [2]

        let lines = DisplayLineBuilder.buildFullFileLines(content: content, changedLines: changedLines)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].lineNumber, 1)
        XCTAssertEqual(lines[0].text, "line one")
        XCTAssertEqual(lines[0].type, .context)

        XCTAssertEqual(lines[1].lineNumber, 2)
        XCTAssertEqual(lines[1].text, "line two")
        XCTAssertEqual(lines[1].type, .addition) // changed line

        XCTAssertEqual(lines[2].lineNumber, 3)
        XCTAssertEqual(lines[2].text, "line three")
        XCTAssertEqual(lines[2].type, .context)
    }

    func testFullFileLinesEmpty() {
        let lines = DisplayLineBuilder.buildFullFileLines(content: "", changedLines: [])
        XCTAssertEqual(lines.count, 1) // one empty line
        XCTAssertEqual(lines[0].text, "")
    }

    func testFullFileLinesNoChanges() {
        let content = "a\nb\nc"
        let lines = DisplayLineBuilder.buildFullFileLines(content: content, changedLines: [])

        XCTAssertTrue(lines.allSatisfy { $0.type == .context })
    }

    // MARK: - Changed Line Extraction

    func testChangedLineNumbers() {
        let hunk = DiffHunk(header: "@@ -1,3 +1,4 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context, text: "same", lineNumber: 1),
            DiffLine(type: .addition, text: "new1", lineNumber: 2),
            DiffLine(type: .addition, text: "new2", lineNumber: 3),
            DiffLine(type: .context, text: "same", lineNumber: 4),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let added = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .addition)
        XCTAssertEqual(added, [2, 3])

        let deleted = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .deletion)
        XCTAssertTrue(deleted.isEmpty)
    }

    // MARK: - Hunk Header Formatting

    func testHunkHeaderFormatting_withContext() {
        let header = DisplayLineBuilder.formatHunkHeader("@@ -10,7 +10,8 @@ func example()")
        XCTAssertTrue(header.contains("func example()"))
        XCTAssertFalse(header.contains("@@"))
    }

    func testHunkHeaderFormatting_noContext() {
        let header = DisplayLineBuilder.formatHunkHeader("@@ -1,5 +1,7 @@")
        XCTAssertFalse(header.contains("@@"))
        XCTAssertTrue(header.contains("─"))
    }

    func testHunkHeaderFormatting_lineRange() {
        let header = DisplayLineBuilder.formatHunkHeader("@@ -1,5 +10,8 @@")
        XCTAssertTrue(header.contains("10"))
    }
}
