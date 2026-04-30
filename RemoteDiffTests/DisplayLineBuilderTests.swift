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

    // MARK: - Side-by-Side Aligned Builder

    func testSideBySide_noChanges_isIdenticalAndAligned() {
        let oldContent = "a\nb\nc"
        let newContent = "a\nb\nc"
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [])

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )

        XCTAssertEqual(result.old.count, 3)
        XCTAssertEqual(result.new.count, 3)
        XCTAssertEqual(result.old.map { $0.text }, ["a", "b", "c"])
        XCTAssertEqual(result.new.map { $0.text }, ["a", "b", "c"])
        XCTAssertTrue(result.old.allSatisfy { $0.type == .context })
        XCTAssertTrue(result.new.allSatisfy { $0.type == .context })
    }

    func testSideBySide_pureAddition_padsOldSide() {
        // Old: line1, line3   New: line1, line2, line3
        let oldContent = "line1\nline3"
        let newContent = "line1\nline2\nline3"
        let hunk = DiffHunk(header: "@@ -1,2 +1,3 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context,  text: "line1", lineNumber: 1),
            DiffLine(type: .addition, text: "line2", lineNumber: 2),
            DiffLine(type: .context,  text: "line3", lineNumber: 3),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk])

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )

        // Both panes must have the same length so they stay aligned.
        XCTAssertEqual(result.old.count, result.new.count)
        XCTAssertEqual(result.new.count, 3)

        // Old side: line1, <pad>, line3
        XCTAssertEqual(result.old[0].text, "line1");  XCTAssertEqual(result.old[0].type, .context)
        XCTAssertEqual(result.old[1].type, .empty);   XCTAssertNil(result.old[1].lineNumber)
        XCTAssertEqual(result.old[2].text, "line3");  XCTAssertEqual(result.old[2].type, .context)

        // New side: line1, line2 (addition), line3
        XCTAssertEqual(result.new[0].text, "line1");  XCTAssertEqual(result.new[0].type, .context)
        XCTAssertEqual(result.new[1].text, "line2");  XCTAssertEqual(result.new[1].type, .addition)
        XCTAssertEqual(result.new[2].text, "line3");  XCTAssertEqual(result.new[2].type, .context)
    }

    func testSideBySide_pureDeletion_padsNewSide() {
        // Old: line1, line2, line3   New: line1, line3
        let oldContent = "line1\nline2\nline3"
        let newContent = "line1\nline3"
        let hunk = DiffHunk(header: "@@ -1,3 +1,2 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context,  text: "line1", lineNumber: 1),
            DiffLine(type: .deletion, text: "line2", lineNumber: 2),
            DiffLine(type: .context,  text: "line3", lineNumber: 3),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk])

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )

        XCTAssertEqual(result.old.count, result.new.count)
        XCTAssertEqual(result.old.count, 3)

        // Old side: line1, line2 (deletion), line3
        XCTAssertEqual(result.old[0].type, .context)
        XCTAssertEqual(result.old[1].type, .deletion); XCTAssertEqual(result.old[1].text, "line2")
        XCTAssertEqual(result.old[2].type, .context)

        // New side: line1, <pad>, line3
        XCTAssertEqual(result.new[0].type, .context); XCTAssertEqual(result.new[0].text, "line1")
        XCTAssertEqual(result.new[1].type, .empty);   XCTAssertNil(result.new[1].lineNumber)
        XCTAssertEqual(result.new[2].type, .context); XCTAssertEqual(result.new[2].text, "line3")
    }

    func testSideBySide_modificationPair_alignsOnSameRow() {
        // line2 is modified — should appear on the SAME row on both sides.
        let oldContent = "a\nfoo\nc"
        let newContent = "a\nbar\nc"
        let hunk = DiffHunk(header: "@@ -1,3 +1,3 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context,  text: "a",   lineNumber: 1),
            DiffLine(type: .deletion, text: "foo", lineNumber: 2),
            DiffLine(type: .addition, text: "bar", lineNumber: 2),
            DiffLine(type: .context,  text: "c",   lineNumber: 3),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk])

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )

        XCTAssertEqual(result.old.count, 3)
        XCTAssertEqual(result.new.count, 3)
        // Row 1 — modification pair on the same Y
        XCTAssertEqual(result.old[1].text, "foo"); XCTAssertEqual(result.old[1].type, .deletion)
        XCTAssertEqual(result.new[1].text, "bar"); XCTAssertEqual(result.new[1].type, .addition)
        // Surrounding context aligned
        XCTAssertEqual(result.old[0].text, result.new[0].text)
        XCTAssertEqual(result.old[2].text, result.new[2].text)
    }

    func testSideBySide_unbalancedHunk_padsCorrectly() {
        // 1 deletion, 3 additions → 1 modification pair + 2 pure additions.
        // Old: a, x, b   New: a, y, p, q, b
        let oldContent = "a\nx\nb"
        let newContent = "a\ny\np\nq\nb"
        let hunk = DiffHunk(header: "@@ -1,3 +1,5 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context,  text: "a", lineNumber: 1),
            DiffLine(type: .deletion, text: "x", lineNumber: 2),
            DiffLine(type: .addition, text: "y", lineNumber: 2),
            DiffLine(type: .addition, text: "p", lineNumber: 3),
            DiffLine(type: .addition, text: "q", lineNumber: 4),
            DiffLine(type: .context,  text: "b", lineNumber: 5),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk])

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )

        XCTAssertEqual(result.old.count, 5)
        XCTAssertEqual(result.new.count, 5)
        // Row 0: "a" context
        XCTAssertEqual(result.old[0].type, .context); XCTAssertEqual(result.new[0].type, .context)
        // Row 1: x ↔ y modification pair
        XCTAssertEqual(result.old[1].type, .deletion); XCTAssertEqual(result.old[1].text, "x")
        XCTAssertEqual(result.new[1].type, .addition); XCTAssertEqual(result.new[1].text, "y")
        // Rows 2,3: pad on old, p/q additions on new
        XCTAssertEqual(result.old[2].type, .empty); XCTAssertEqual(result.new[2].type, .addition)
        XCTAssertEqual(result.old[3].type, .empty); XCTAssertEqual(result.new[3].type, .addition)
        XCTAssertEqual(result.new[2].text, "p")
        XCTAssertEqual(result.new[3].text, "q")
        // Row 4: "b" context aligned
        XCTAssertEqual(result.old[4].text, "b"); XCTAssertEqual(result.new[4].text, "b")
    }

    func testSideBySide_keepsAlignmentAcrossMultipleHunks() {
        // Two separate hunks with unchanged regions in between.
        // Old: 1,2,3,4,5,6,7  New: 1,2,A,4,5,B,7
        let oldContent = (1...7).map(String.init).joined(separator: "\n")
        let newContent = "1\n2\nA\n4\n5\nB\n7"
        let hunk1 = DiffHunk(header: "@@ -3,1 +3,1 @@", leftStartLine: 3, rightStartLine: 3, lines: [
            DiffLine(type: .deletion, text: "3", lineNumber: 3),
            DiffLine(type: .addition, text: "A", lineNumber: 3),
        ])
        let hunk2 = DiffHunk(header: "@@ -6,1 +6,1 @@", leftStartLine: 6, rightStartLine: 6, lines: [
            DiffLine(type: .deletion, text: "6", lineNumber: 6),
            DiffLine(type: .addition, text: "B", lineNumber: 6),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk1, hunk2])

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )

        XCTAssertEqual(result.old.count, 7)
        XCTAssertEqual(result.new.count, 7)
        // Row 2: 3 ↔ A
        XCTAssertEqual(result.old[2].text, "3"); XCTAssertEqual(result.old[2].type, .deletion)
        XCTAssertEqual(result.new[2].text, "A"); XCTAssertEqual(result.new[2].type, .addition)
        // Row 5: 6 ↔ B
        XCTAssertEqual(result.old[5].text, "6"); XCTAssertEqual(result.old[5].type, .deletion)
        XCTAssertEqual(result.new[5].text, "B"); XCTAssertEqual(result.new[5].type, .addition)
        // Untouched rows match
        XCTAssertEqual(result.old[0].text, result.new[0].text)  // "1"
        XCTAssertEqual(result.old[3].text, result.new[3].text)  // "4"
        XCTAssertEqual(result.old[6].text, result.new[6].text)  // "7"
    }

    func testSideBySide_inlineRangesAreAppliedToModificationPairs() {
        let oldContent = "foo"
        let newContent = "bar"
        let hunk = DiffHunk(header: "@@ -1,1 +1,1 @@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .deletion, text: "foo", lineNumber: 1),
            DiffLine(type: .addition, text: "bar", lineNumber: 1),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk])
        let oldRanges: [Int: [NSRange]] = [1: [NSRange(location: 0, length: 3)]]
        let newRanges: [Int: [NSRange]] = [1: [NSRange(location: 0, length: 3)]]

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff,
            oldInlineRanges: oldRanges, newInlineRanges: newRanges
        )

        XCTAssertEqual(result.old[0].inlineRanges.count, 1)
        XCTAssertEqual(result.new[0].inlineRanges.count, 1)
        XCTAssertEqual(result.old[0].inlineRanges[0].length, 3)
    }

    func testSideBySide_emptyFiles_returnEmptyArrays() {
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [])
        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: "", newContent: "", fileDiff: fileDiff
        )
        XCTAssertTrue(result.old.isEmpty)
        XCTAssertTrue(result.new.isEmpty)
    }

    // MARK: - Connector Link

    func testConnectorLink_pureDeletion_collapsesNewSide() {
        // 2 deletions, 0 additions — the link should span 2 old lines and a
        // zero-width range on the new side.
        let hunk = DiffHunk(header: "@@", leftStartLine: 5, rightStartLine: 5, lines: [
            DiffLine(type: .deletion, text: "a", lineNumber: 5),
            DiffLine(type: .deletion, text: "b", lineNumber: 6),
        ])
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])
        let links = ConnectorLink.compute(fileDiff: fileDiff)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].kind, .deletion)
        XCTAssertEqual(links[0].oldStartLine, 5)
        XCTAssertEqual(links[0].oldEndLine, 7)   // exclusive
        XCTAssertEqual(links[0].oldRowCount, 2)
        XCTAssertEqual(links[0].newStartLine, 5)
        XCTAssertEqual(links[0].newEndLine, 5)   // collapsed
        XCTAssertEqual(links[0].newRowCount, 0)
    }

    func testConnectorLink_pureAddition_collapsesOldSide() {
        let hunk = DiffHunk(header: "@@", leftStartLine: 10, rightStartLine: 10, lines: [
            DiffLine(type: .addition, text: "a", lineNumber: 10),
            DiffLine(type: .addition, text: "b", lineNumber: 11),
            DiffLine(type: .addition, text: "c", lineNumber: 12),
        ])
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])
        let links = ConnectorLink.compute(fileDiff: fileDiff)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].kind, .addition)
        XCTAssertEqual(links[0].newStartLine, 10)
        XCTAssertEqual(links[0].newEndLine, 13)
        XCTAssertEqual(links[0].newRowCount, 3)
        XCTAssertEqual(links[0].oldStartLine, 10)
        XCTAssertEqual(links[0].oldEndLine, 10)  // collapsed
        XCTAssertEqual(links[0].oldRowCount, 0)
    }

    func testConnectorLink_modification_bothSides() {
        // 1 deletion + 9 additions — a typical "docstring expanded" change.
        var lines: [DiffLine] = [
            DiffLine(type: .deletion, text: "old", lineNumber: 253),
        ]
        for k in 0..<9 {
            lines.append(DiffLine(type: .addition, text: "new\(k)", lineNumber: 253 + k))
        }
        let hunk = DiffHunk(header: "@@", leftStartLine: 253, rightStartLine: 253, lines: lines)
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])
        let links = ConnectorLink.compute(fileDiff: fileDiff)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].kind, .modification)
        XCTAssertEqual(links[0].oldStartLine, 253); XCTAssertEqual(links[0].oldEndLine, 254)
        XCTAssertEqual(links[0].newStartLine, 253); XCTAssertEqual(links[0].newEndLine, 262)
        XCTAssertEqual(links[0].oldRowCount, 1)
        XCTAssertEqual(links[0].newRowCount, 9)
    }

    func testConnectorLink_advancesPastContextBetweenChanges() {
        // context, deletion, addition, context, deletion, addition
        let hunk = DiffHunk(header: "@@", leftStartLine: 1, rightStartLine: 1, lines: [
            DiffLine(type: .context,  text: "ctx1", lineNumber: 1),
            DiffLine(type: .deletion, text: "d1",   lineNumber: 2),
            DiffLine(type: .addition, text: "a1",   lineNumber: 2),
            DiffLine(type: .context,  text: "ctx2", lineNumber: 3),
            DiffLine(type: .deletion, text: "d2",   lineNumber: 4),
            DiffLine(type: .addition, text: "a2",   lineNumber: 4),
        ])
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])
        let links = ConnectorLink.compute(fileDiff: fileDiff)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].oldStartLine, 2); XCTAssertEqual(links[0].oldEndLine, 3)
        XCTAssertEqual(links[0].newStartLine, 2); XCTAssertEqual(links[0].newEndLine, 3)
        XCTAssertEqual(links[1].oldStartLine, 4); XCTAssertEqual(links[1].oldEndLine, 5)
        XCTAssertEqual(links[1].newStartLine, 4); XCTAssertEqual(links[1].newEndLine, 5)
        XCTAssertTrue(links.allSatisfy { $0.kind == .modification })
    }

    func testConnectorLink_multipleHunksProduceMultipleLinks() {
        let hunk1 = DiffHunk(header: "@@1", leftStartLine: 10, rightStartLine: 10, lines: [
            DiffLine(type: .deletion, text: "a", lineNumber: 10),
        ])
        let hunk2 = DiffHunk(header: "@@2", leftStartLine: 100, rightStartLine: 99, lines: [
            DiffLine(type: .addition, text: "b", lineNumber: 99),
            DiffLine(type: .addition, text: "c", lineNumber: 100),
        ])
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk1, hunk2])
        let links = ConnectorLink.compute(fileDiff: fileDiff)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].kind, .deletion)
        XCTAssertEqual(links[1].kind, .addition)
        XCTAssertEqual(links[1].newStartLine, 99)
        XCTAssertEqual(links[1].newEndLine, 101)
    }

    func testConnectorLink_emptyDiff_producesNoLinks() {
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [])
        XCTAssertTrue(ConnectorLink.compute(fileDiff: fileDiff).isEmpty)
    }

    func testConnectorLink_interleavedDelAdd_collapseToSingleLink() {
        // [del, add, del, add] with no context between — should be ONE link
        // covering both edits, not two separate links.
        let hunk = DiffHunk(header: "@@", leftStartLine: 75, rightStartLine: 75, lines: [
            DiffLine(type: .deletion, text: "firstName: old", lineNumber: 75),
            DiffLine(type: .addition, text: "firstName: new", lineNumber: 75),
            DiffLine(type: .deletion, text: "lastName: old",  lineNumber: 76),
            DiffLine(type: .addition, text: "lastName: new",  lineNumber: 76),
        ])
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])
        let links = ConnectorLink.compute(fileDiff: fileDiff)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].kind, .modification)
        XCTAssertEqual(links[0].oldStartLine, 75); XCTAssertEqual(links[0].oldEndLine, 77)
        XCTAssertEqual(links[0].newStartLine, 75); XCTAssertEqual(links[0].newEndLine, 77)
    }

    // MARK: - Modified Line Numbers

    func testModifiedLineNumbers_emptyForPureAddition() {
        let hunk = DiffHunk(header: "@@", leftStartLine: 5, rightStartLine: 5, lines: [
            DiffLine(type: .addition, text: "a", lineNumber: 5),
            DiffLine(type: .addition, text: "b", lineNumber: 6),
        ])
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])
        XCTAssertTrue(DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .right).isEmpty)
        XCTAssertTrue(DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .left).isEmpty)
    }

    func testModifiedLineNumbers_emptyForPureDeletion() {
        let hunk = DiffHunk(header: "@@", leftStartLine: 5, rightStartLine: 5, lines: [
            DiffLine(type: .deletion, text: "a", lineNumber: 5),
            DiffLine(type: .deletion, text: "b", lineNumber: 6),
        ])
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])
        XCTAssertTrue(DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .left).isEmpty)
        XCTAssertTrue(DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .right).isEmpty)
    }

    func testModifiedLineNumbers_collectsBothSidesForModification() {
        // 1 deletion + 9 additions — line 253 on left and 253…261 on right.
        var lines: [DiffLine] = [DiffLine(type: .deletion, text: "old", lineNumber: 253)]
        for k in 0..<9 {
            lines.append(DiffLine(type: .addition, text: "new\(k)", lineNumber: 253 + k))
        }
        let hunk = DiffHunk(header: "@@", leftStartLine: 253, rightStartLine: 253, lines: lines)
        let fileDiff = FileDiff(oldPath: "x", newPath: "x", isBinary: false, hunks: [hunk])

        XCTAssertEqual(DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .left), [253])
        XCTAssertEqual(DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .right),
                       Set(253..<262))
    }

    // MARK: - buildFullFileLines with modifiedLines

    func testFullFileLines_modifiedLinesGetModificationType() {
        let content = "a\nb\nc"
        let lines = DisplayLineBuilder.buildFullFileLines(
            content: content,
            changedLines: [2, 3],          // both 2 and 3 are changed
            highlightType: .addition,
            modifiedLines: [2]              // line 2 is a modification, line 3 is a pure addition
        )
        XCTAssertEqual(lines[0].type, .context)
        XCTAssertEqual(lines[1].type, .modification)
        XCTAssertEqual(lines[2].type, .addition)
    }

    func testFullFileLines_modifiedLinesTakePrecedenceOverHighlightType() {
        // A line that's both in changedLines and modifiedLines should be tagged
        // .modification, not the (now overridden) highlightType.
        let content = "only one line"
        let lines = DisplayLineBuilder.buildFullFileLines(
            content: content,
            changedLines: [1],
            highlightType: .deletion,
            modifiedLines: [1]
        )
        XCTAssertEqual(lines[0].type, .modification)
    }

    // MARK: - Change Region

    /// Helper to build a DisplayLine with a specific type for region tests.
    private func dl(_ type: DiffLineType, _ id: String = UUID().uuidString,
                    isHunkHeader: Bool = false) -> DisplayLine {
        DisplayLine(id: id, lineNumber: nil, text: "", type: type, isHunkHeader: isHunkHeader)
    }

    func testChangeRegion_emptyInput() {
        XCTAssertTrue(ChangeRegion.compute(left: [], right: []).isEmpty)
    }

    func testChangeRegion_allContext_noRegions() {
        let left  = [dl(.context), dl(.context), dl(.context)]
        let right = [dl(.context), dl(.context), dl(.context)]
        XCTAssertTrue(ChangeRegion.compute(left: left, right: right).isEmpty)
    }

    func testChangeRegion_pureAddition_singleRegion() {
        // Row 1: padding on old, addition on new
        let left  = [dl(.context), dl(.empty),    dl(.context)]
        let right = [dl(.context), dl(.addition), dl(.context)]
        let regions = ChangeRegion.compute(left: left, right: right)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startRow, 1)
        XCTAssertEqual(regions[0].endRow, 1)
        XCTAssertEqual(regions[0].kind, .addition)
        XCTAssertEqual(regions[0].rowCount, 1)
    }

    func testChangeRegion_pureDeletion_singleRegion() {
        let left  = [dl(.context), dl(.deletion), dl(.context)]
        let right = [dl(.context), dl(.empty),    dl(.context)]
        let regions = ChangeRegion.compute(left: left, right: right)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].kind, .deletion)
        XCTAssertEqual(regions[0].startRow, 1)
        XCTAssertEqual(regions[0].endRow, 1)
    }

    func testChangeRegion_modificationPair_classifiedAsModification() {
        let left  = [dl(.deletion)]
        let right = [dl(.addition)]
        let regions = ChangeRegion.compute(left: left, right: right)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].kind, .modification)
    }

    func testChangeRegion_mixedRunIsSingleModificationRegion() {
        // 3 contiguous changed rows: pure-addition, modification pair, pure-deletion.
        // Should collapse into ONE region classified as modification.
        let left = [
            dl(.context),
            dl(.empty),     // pure addition
            dl(.deletion),  // mod pair
            dl(.deletion),  // pure deletion
            dl(.context),
        ]
        let right = [
            dl(.context),
            dl(.addition),  // pure addition
            dl(.addition),  // mod pair
            dl(.empty),     // pure deletion
            dl(.context),
        ]
        let regions = ChangeRegion.compute(left: left, right: right)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startRow, 1)
        XCTAssertEqual(regions[0].endRow, 3)
        XCTAssertEqual(regions[0].kind, .modification)
        XCTAssertEqual(regions[0].rowCount, 3)
    }

    func testChangeRegion_multipleSeparateRegions() {
        let left = [
            dl(.deletion),  // region 1
            dl(.context),
            dl(.empty),     // region 2
            dl(.context),
            dl(.deletion),  // region 3
        ]
        let right = [
            dl(.empty),
            dl(.context),
            dl(.addition),
            dl(.context),
            dl(.addition),
        ]
        let regions = ChangeRegion.compute(left: left, right: right)
        XCTAssertEqual(regions.count, 3)
        XCTAssertEqual(regions[0].kind, .deletion)
        XCTAssertEqual(regions[1].kind, .addition)
        XCTAssertEqual(regions[2].kind, .modification)
        XCTAssertEqual(regions[0].startRow, 0); XCTAssertEqual(regions[0].endRow, 0)
        XCTAssertEqual(regions[1].startRow, 2); XCTAssertEqual(regions[1].endRow, 2)
        XCTAssertEqual(regions[2].startRow, 4); XCTAssertEqual(regions[2].endRow, 4)
    }

    func testChangeRegion_hunkHeadersSeparateRegions() {
        // In Diff mode the panes contain hunk headers — a header should split a
        // would-be-contiguous run into two regions.
        let left = [
            dl(.deletion),
            dl(.context, isHunkHeader: true),
            dl(.deletion),
        ]
        let right = [
            dl(.addition),
            dl(.context, isHunkHeader: true),
            dl(.addition),
        ]
        let regions = ChangeRegion.compute(left: left, right: right)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].startRow, 0); XCTAssertEqual(regions[0].endRow, 0)
        XCTAssertEqual(regions[1].startRow, 2); XCTAssertEqual(regions[1].endRow, 2)
    }

    func testChangeRegion_mismatchedLengths_returnsEmpty() {
        let left  = [dl(.context)]
        let right = [dl(.context), dl(.addition)]
        XCTAssertTrue(ChangeRegion.compute(left: left, right: right).isEmpty)
    }

    func testChangeRegion_endToEndWithAlignedBuilder() {
        // Integration-style test: build aligned arrays via the public builder,
        // then verify ChangeRegion picks them up correctly.
        let oldContent = "a\nb\nc\nd"
        let newContent = "a\nB\nc\nE\nd"
        let hunk = DiffHunk(header: "@@", leftStartLine: 2, rightStartLine: 2, lines: [
            DiffLine(type: .deletion, text: "b", lineNumber: 2),
            DiffLine(type: .addition, text: "B", lineNumber: 2),
            DiffLine(type: .context,  text: "c", lineNumber: 3),
            DiffLine(type: .addition, text: "E", lineNumber: 4),
            DiffLine(type: .context,  text: "d", lineNumber: 5),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk])
        let aligned = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )
        let regions = ChangeRegion.compute(left: aligned.old, right: aligned.new)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].kind, .modification)  // b ↔ B
        XCTAssertEqual(regions[1].kind, .addition)      // pure +E
    }

    func testSideBySide_newSideUsesFilePrefixForScrollAnchors() {
        // The new side's IDs must be `file-N` so existing change-navigation
        // (changeAnchors -> file-N) keeps working.
        let oldContent = "a\nb"
        let newContent = "a\nB"
        let hunk = DiffHunk(header: "@@ -2,1 +2,1 @@", leftStartLine: 2, rightStartLine: 2, lines: [
            DiffLine(type: .deletion, text: "b", lineNumber: 2),
            DiffLine(type: .addition, text: "B", lineNumber: 2),
        ])
        let fileDiff = FileDiff(oldPath: "x.txt", newPath: "x.txt", isBinary: false, hunks: [hunk])

        let result = DisplayLineBuilder.buildSideBySideLines(
            oldContent: oldContent, newContent: newContent, fileDiff: fileDiff
        )

        XCTAssertTrue(result.new.contains { $0.id == "file-2" && $0.type == .addition })
        XCTAssertTrue(result.old.contains { $0.id == "old-2"  && $0.type == .deletion })
    }
}
