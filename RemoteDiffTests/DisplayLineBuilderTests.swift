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

    func testFullFileLinesWithDeletionHighlightType() {
        let content = "line one\nline two\nline three"
        let changedLines: Set<Int> = [2]

        let lines = DisplayLineBuilder.buildFullFileLines(
            content: content, changedLines: changedLines, highlightType: .deletion
        )

        XCTAssertEqual(lines[0].type, .context)
        XCTAssertEqual(lines[1].type, .deletion)  // deletion, not addition
        XCTAssertEqual(lines[2].type, .context)
    }

    func testFullFileLinesWithInlineRangesMap() {
        let content = "aaa\nbbb\nccc"
        let changedLines: Set<Int> = [2]
        let inlineMap: [Int: [NSRange]] = [2: [NSRange(location: 0, length: 3)]]

        let lines = DisplayLineBuilder.buildFullFileLines(
            content: content, changedLines: changedLines, inlineRangesMap: inlineMap
        )

        XCTAssertTrue(lines[0].inlineRanges.isEmpty)
        XCTAssertEqual(lines[1].inlineRanges.count, 1)
        XCTAssertEqual(lines[1].inlineRanges[0], NSRange(location: 0, length: 3))
        XCTAssertTrue(lines[2].inlineRanges.isEmpty)
    }

    func testInlineRangesMap_fromFileDiff() {
        let hunk = DiffHunk(header: "@@ -1,1 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "let x = 1", lineNumber: 1),
            DiffLine(type: .addition, text: "let x = 2", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "a.swift", newPath: "a.swift", isBinary: false, hunks: [hunk])

        let maps = DisplayLineBuilder.inlineRangesMap(fileDiff: fileDiff)

        // Both old and new should have inline ranges for line 1
        XCTAssertEqual(maps.old[1]?.count, 1)
        XCTAssertEqual(maps.new[1]?.count, 1)
        XCTAssertEqual(maps.old[1]?[0], NSRange(location: 8, length: 1))
        XCTAssertEqual(maps.new[1]?[0], NSRange(location: 8, length: 1))
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

    // MARK: - Inline Diff Ranges

    func testInlineRanges_simpleChange() {
        let (oldRanges, newRanges) = DisplayLineBuilder.computeInlineRanges(
            oldText: "let id = UUID()",
            newText: "let id: String"
        )
        // Common prefix: "let id"  (6 chars)
        // Common suffix: "" (nothing)
        // Old change: " = UUID()" at 6..<15  (length 9)
        // New change: ": String"  at 6..<14  (length 8)
        XCTAssertEqual(oldRanges.count, 1)
        XCTAssertEqual(oldRanges[0].location, 6)
        XCTAssertEqual(oldRanges[0].length, 9)
        XCTAssertEqual(newRanges.count, 1)
        XCTAssertEqual(newRanges[0].location, 6)
        XCTAssertEqual(newRanges[0].length, 8)
    }

    func testInlineRanges_middleChange() {
        let (oldRanges, newRanges) = DisplayLineBuilder.computeInlineRanges(
            oldText: "color = red;",
            newText: "color = blue;"
        )
        // Common prefix: "color = " (8)
        // Common suffix: ";" (1)
        // Old change: "red" at 8..<11  (length 3)
        // New change: "blue" at 8..<12 (length 4)
        XCTAssertEqual(oldRanges.count, 1)
        XCTAssertEqual(oldRanges[0], NSRange(location: 8, length: 3))
        XCTAssertEqual(newRanges.count, 1)
        XCTAssertEqual(newRanges[0], NSRange(location: 8, length: 4))
    }

    func testInlineRanges_identicalLines() {
        let (oldRanges, newRanges) = DisplayLineBuilder.computeInlineRanges(
            oldText: "same text",
            newText: "same text"
        )
        XCTAssertTrue(oldRanges.isEmpty)
        XCTAssertTrue(newRanges.isEmpty)
    }

    func testInlineRanges_completelyDifferent() {
        let (oldRanges, newRanges) = DisplayLineBuilder.computeInlineRanges(
            oldText: "abc",
            newText: "xyz"
        )
        XCTAssertEqual(oldRanges.count, 1)
        XCTAssertEqual(oldRanges[0], NSRange(location: 0, length: 3))
        XCTAssertEqual(newRanges.count, 1)
        XCTAssertEqual(newRanges[0], NSRange(location: 0, length: 3))
    }

    func testInlineRanges_emptyOld() {
        let (oldRanges, newRanges) = DisplayLineBuilder.computeInlineRanges(
            oldText: "",
            newText: "new content"
        )
        XCTAssertTrue(oldRanges.isEmpty)
        XCTAssertEqual(newRanges.count, 1)
        XCTAssertEqual(newRanges[0], NSRange(location: 0, length: 11))
    }

    func testInlineRanges_suffixOnlyChange() {
        let (oldRanges, newRanges) = DisplayLineBuilder.computeInlineRanges(
            oldText: "hello world",
            newText: "hello earth"
        )
        // Common prefix: "hello " (6)
        // Common suffix: "" (nothing, 'd' != 'h')
        // Actually: old="hello world", new="hello earth"
        // prefix: "hello " (6), suffix: "" (d != h, then l != t, etc.)
        // Wait: old ends with 'd', new ends with 'h' — no common suffix
        XCTAssertEqual(oldRanges.count, 1)
        XCTAssertEqual(oldRanges[0], NSRange(location: 6, length: 5))
        XCTAssertEqual(newRanges.count, 1)
        XCTAssertEqual(newRanges[0], NSRange(location: 6, length: 5))
    }

    // MARK: - Inline Ranges in buildDiffLines

    func testBuildDiffLines_inlineRangesForModifiedPair() {
        let hunk = DiffHunk(header: "@@ -1,1 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "let x = 1", lineNumber: 1),
            DiffLine(type: .addition, text: "let x = 2", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "a.swift", newPath: "a.swift", isBinary: false, hunks: [hunk])

        let leftLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)
        let rightLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .right)

        let leftContent = leftLines.filter { !$0.isHunkHeader }
        let rightContent = rightLines.filter { !$0.isHunkHeader }

        // Both sides should have inline ranges highlighting the "1" → "2" change
        XCTAssertFalse(leftContent[0].inlineRanges.isEmpty)
        XCTAssertFalse(rightContent[0].inlineRanges.isEmpty)
        // "let x = " is 8 chars, then "1"/"2" differ
        XCTAssertEqual(leftContent[0].inlineRanges[0], NSRange(location: 8, length: 1))
        XCTAssertEqual(rightContent[0].inlineRanges[0], NSRange(location: 8, length: 1))
    }

    func testBuildDiffLines_noInlineRangesForContextLines() {
        let hunk = DiffHunk(header: "@@ -1,1 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context, text: "unchanged", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "a.swift", newPath: "a.swift", isBinary: false, hunks: [hunk])

        let lines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)
        let contentLines = lines.filter { !$0.isHunkHeader }

        XCTAssertTrue(contentLines[0].inlineRanges.isEmpty)
    }

    func testBuildDiffLines_noInlineRangesForStandaloneAddition() {
        let hunk = DiffHunk(header: "@@ -1,0 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .addition, text: "brand new line", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "a.swift", newPath: "a.swift", isBinary: false, hunks: [hunk])

        let rightLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .right)
        let content = rightLines.filter { !$0.isHunkHeader }

        // Standalone addition (no paired deletion) should have no inline ranges
        XCTAssertTrue(content[0].inlineRanges.isEmpty)
    }

    // MARK: - Deletion Marker Positions

    func testDeletionMarkers_pureDeletion() {
        // old: context(1), deletion(2), deletion(3), context(4→new:2)
        let hunk = DiffHunk(header: "@@ -1,4 +1,2 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context, text: "A", lineNumber: 1),
            DiffLine(type: .deletion, text: "B", lineNumber: 2),
            DiffLine(type: .deletion, text: "C", lineNumber: 3),
            DiffLine(type: .context, text: "D", lineNumber: 2),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let markers = DisplayLineBuilder.deletionMarkerPositions(fileDiff: fileDiff)

        // Deletions occur after new-file line 1 (between "A" and "D")
        XCTAssertEqual(markers, [1])
    }

    func testDeletionMarkers_modificationNotMarked() {
        // 1 deletion + 1 addition = modification, not pure deletion
        let hunk = DiffHunk(header: "@@ -1,1 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "old", lineNumber: 1),
            DiffLine(type: .addition, text: "new", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let markers = DisplayLineBuilder.deletionMarkerPositions(fileDiff: fileDiff)

        // No marker — it's a modification, not a deletion
        XCTAssertTrue(markers.isEmpty)
    }

    func testDeletionMarkers_deletionAtStartOfFile() {
        // Deletions at the very beginning, before any new-file content
        let hunk = DiffHunk(header: "@@ -1,3 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "removed1", lineNumber: 1),
            DiffLine(type: .deletion, text: "removed2", lineNumber: 2),
            DiffLine(type: .context, text: "kept", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let markers = DisplayLineBuilder.deletionMarkerPositions(fileDiff: fileDiff)

        // Marker at position 0 = before the first line
        XCTAssertEqual(markers, [0])
    }

    func testDeletionMarkers_moreDeletionsThanAdditions() {
        // 3 deletions + 1 addition = 1 modification + 2 pure deletions
        let hunk = DiffHunk(header: "@@ -1,4 +1,2 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context, text: "ctx", lineNumber: 1),
            DiffLine(type: .deletion, text: "old1", lineNumber: 2),
            DiffLine(type: .deletion, text: "old2", lineNumber: 3),
            DiffLine(type: .deletion, text: "old3", lineNumber: 4),
            DiffLine(type: .addition, text: "new1", lineNumber: 2),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let markers = DisplayLineBuilder.deletionMarkerPositions(fileDiff: fileDiff)

        // 3 deletions, 1 addition → pure deletions exist → marker after the addition
        // markerPos starts at 1 (newLine-1 before deletions), then addCount=1 → marker at 1+1=2
        XCTAssertEqual(markers, [2])
    }

    func testDeletionMarkers_noDeletions() {
        let hunk = DiffHunk(header: "@@ -1,1 +1,2 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context, text: "A", lineNumber: 1),
            DiffLine(type: .addition, text: "B", lineNumber: 2),
        ])
        let fileDiff = FileDiff(oldPath: "a.txt", newPath: "a.txt", isBinary: false, hunks: [hunk])

        let markers = DisplayLineBuilder.deletionMarkerPositions(fileDiff: fileDiff)

        XCTAssertTrue(markers.isEmpty)
    }
}
