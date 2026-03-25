import Foundation

// MARK: - Display Line

/// A unified line model for rendering in any view mode (diff, full file, side-by-side).
struct DisplayLine: Identifiable, Equatable {
    let id: String
    let lineNumber: Int?
    let text: String
    let type: DiffLineType
    let isHunkHeader: Bool
    /// Character ranges within `text` that represent the actual inline change
    /// (word-level diff highlighting). Empty for context/hunk/unmodified lines.
    let inlineRanges: [NSRange]

    init(id: String, lineNumber: Int? = nil, text: String, type: DiffLineType = .context,
         isHunkHeader: Bool = false, inlineRanges: [NSRange] = []) {
        self.id = id
        self.lineNumber = lineNumber
        self.text = text
        self.type = type
        self.isHunkHeader = isHunkHeader
        self.inlineRanges = inlineRanges
    }
}

// MARK: - Display Line Builder

enum DisplayLineBuilder {

    enum Side { case left, right }

    // MARK: - Diff Mode

    /// Builds display lines for one side of a diff view.
    static func buildDiffLines(fileDiff: FileDiff, side: Side) -> [DisplayLine] {
        var result: [DisplayLine] = []

        for (hunkIdx, hunk) in fileDiff.hunks.enumerated() {
            // Hunk header
            result.append(DisplayLine(
                id: "hunk-\(hunkIdx)",
                text: formatHunkHeader(hunk.header),
                isHunkHeader: true
            ))

            // Paired lines
            for (pairIdx, pair) in hunk.pairedLines.enumerated() {
                let line = side == .left ? pair.left : pair.right

                // Compute inline highlight ranges for modification pairs (deletion ↔ addition)
                var inlineRanges: [NSRange] = []
                if let left = pair.left, let right = pair.right,
                   left.type == .deletion, right.type == .addition {
                    let (oldRanges, newRanges) = computeInlineRanges(oldText: left.text, newText: right.text)
                    inlineRanges = side == .left ? oldRanges : newRanges
                }

                result.append(DisplayLine(
                    id: "hunk-\(hunkIdx)-line-\(pairIdx)",
                    lineNumber: line?.lineNumber,
                    text: line?.text ?? "",
                    type: line?.type ?? .empty,
                    inlineRanges: inlineRanges
                ))
            }
        }

        return result
    }

    // MARK: - Inline Diff

    /// Computes character ranges that differ between two strings (common prefix/suffix algorithm).
    /// Returns ranges relative to each string's content.
    static func computeInlineRanges(oldText: String, newText: String) -> (oldRanges: [NSRange], newRanges: [NSRange]) {
        let oldChars = Array(oldText.utf16)
        let newChars = Array(newText.utf16)

        // Find common prefix length
        var prefixLen = 0
        while prefixLen < oldChars.count && prefixLen < newChars.count
              && oldChars[prefixLen] == newChars[prefixLen] {
            prefixLen += 1
        }

        // Find common suffix length (not overlapping with prefix)
        var suffixLen = 0
        while suffixLen < (oldChars.count - prefixLen)
              && suffixLen < (newChars.count - prefixLen)
              && oldChars[oldChars.count - 1 - suffixLen] == newChars[newChars.count - 1 - suffixLen] {
            suffixLen += 1
        }

        let oldStart = prefixLen
        let oldEnd = oldChars.count - suffixLen
        let newStart = prefixLen
        let newEnd = newChars.count - suffixLen

        let oldRanges = oldStart < oldEnd ? [NSRange(location: oldStart, length: oldEnd - oldStart)] : []
        let newRanges = newStart < newEnd ? [NSRange(location: newStart, length: newEnd - newStart)] : []

        return (oldRanges, newRanges)
    }

    // MARK: - Full File Mode

    /// Builds display lines for a full file view, highlighting changed lines.
    /// - `highlightType`: the diff type for changed lines (`.addition` for new file, `.deletion` for old file)
    /// - `inlineRangesMap`: optional per-line inline highlight ranges (line number → ranges)
    static func buildFullFileLines(content: String, changedLines: Set<Int>,
                                   highlightType: DiffLineType = .addition,
                                   inlineRangesMap: [Int: [NSRange]] = [:]) -> [DisplayLine] {
        let lines = content.components(separatedBy: "\n")
        return lines.enumerated().map { index, text in
            let lineNum = index + 1
            let type: DiffLineType = changedLines.contains(lineNum) ? highlightType : .context
            return DisplayLine(
                id: "file-\(lineNum)",
                lineNumber: lineNum,
                text: text,
                type: type,
                inlineRanges: inlineRangesMap[lineNum] ?? []
            )
        }
    }

    /// Builds a mapping from line numbers to inline highlight ranges using diff hunk data.
    /// Returns separate maps for old-file and new-file sides.
    static func inlineRangesMap(fileDiff: FileDiff) -> (old: [Int: [NSRange]], new: [Int: [NSRange]]) {
        var oldMap: [Int: [NSRange]] = [:]
        var newMap: [Int: [NSRange]] = [:]

        for hunk in fileDiff.hunks {
            for pair in hunk.pairedLines {
                guard let left = pair.left, let right = pair.right,
                      left.type == .deletion, right.type == .addition,
                      let oldNum = left.lineNumber, let newNum = right.lineNumber else { continue }

                let (oldRanges, newRanges) = computeInlineRanges(oldText: left.text, newText: right.text)
                if !oldRanges.isEmpty { oldMap[oldNum] = oldRanges }
                if !newRanges.isEmpty { newMap[newNum] = newRanges }
            }
        }

        return (oldMap, newMap)
    }

    // MARK: - Deletion Markers

    /// Returns line numbers in the **new file** after which pure deletions occurred.
    /// A thin red marker line should be drawn below these line numbers on the new-file pane.
    /// Returns 0 if deletions occur before the first line.
    static func deletionMarkerPositions(fileDiff: FileDiff) -> Set<Int> {
        var markers = Set<Int>()

        for hunk in fileDiff.hunks {
            var newLine = hunk.rightStartLine
            var i = 0
            let lines = hunk.lines

            while i < lines.count {
                switch lines[i].type {
                case .context:
                    newLine += 1
                    i += 1
                case .addition:
                    newLine += 1
                    i += 1
                case .deletion:
                    // Track position before deletions start
                    let markerPos = newLine - 1

                    // Collect consecutive deletions
                    var delCount = 0
                    while i < lines.count && lines[i].type == .deletion {
                        delCount += 1
                        i += 1
                    }
                    // Collect following additions (these pair with some deletions = modifications)
                    var addCount = 0
                    while i < lines.count && lines[i].type == .addition {
                        addCount += 1
                        newLine += 1
                        i += 1
                    }
                    // Pure deletions exist when there are more deletions than additions
                    if delCount > addCount {
                        markers.insert(max(markerPos + addCount, 0))
                    }
                case .empty:
                    i += 1
                }
            }
        }

        return markers
    }

    // MARK: - Changed Line Extraction

    /// Extracts line numbers that have a specific change type from a diff.
    static func changedLineNumbers(fileDiff: FileDiff, type: DiffLineType) -> Set<Int> {
        var nums = Set<Int>()
        for hunk in fileDiff.hunks {
            for line in hunk.lines where line.type == type {
                if let n = line.lineNumber { nums.insert(n) }
            }
        }
        return nums
    }

    // MARK: - Hunk Header Formatting

    /// Formats a raw hunk header into a readable display string.
    /// "@@ -10,7 +10,8 @@ func example()" → "───── lines 10–17  func example() ─────"
    static func formatHunkHeader(_ header: String) -> String {
        let context = extractContext(from: header)
        let lineInfo = extractLineInfo(from: header)

        var text = "───── \(lineInfo)"
        if !context.isEmpty { text += "  \(context)" }
        text += " ─────"
        return text
    }

    // MARK: - Private

    private static func extractContext(from header: String) -> String {
        let pattern = #"^@@ [^@]+ @@\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let range = Range(match.range(at: 1), in: header) else { return "" }
        return String(header[range]).trimmingCharacters(in: .whitespaces)
    }

    private static func extractLineInfo(from header: String) -> String {
        let pattern = #"\+(\d+)(?:,(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let startRange = Range(match.range(at: 1), in: header),
              let start = Int(header[startRange]) else { return "" }

        if match.range(at: 2).location != NSNotFound,
           let countRange = Range(match.range(at: 2), in: header),
           let count = Int(header[countRange]), count > 1 {
            return "lines \(start)–\(start + count - 1)"
        }
        return "line \(start)"
    }
}
