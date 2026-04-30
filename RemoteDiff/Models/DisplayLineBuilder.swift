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

// MARK: - Connector Link

/// A single change in a unified diff, expressed as **two separate line ranges**
/// — one in the old file and one in the new file. Used by the connector ribbon
/// view to draw cubic Bézier curves between the two unaligned panes of a
/// side-by-side diff.
///
/// Both ranges are 1-based and use exclusive end. Either range may be empty
/// (start == end) for pure additions or pure deletions — in that case the
/// ribbon collapses to a point on that side, producing a wedge shape.
struct ConnectorLink: Equatable {
    enum Kind: Equatable {
        case addition       // pure addition: oldStartLine == oldEndLine
        case deletion       // pure deletion: newStartLine == newEndLine
        case modification   // both ranges non-empty (deletions paired with additions)
    }
    let oldStartLine: Int
    let oldEndLine: Int     // exclusive
    let newStartLine: Int
    let newEndLine: Int     // exclusive
    let kind: Kind

    /// Number of old-file lines this link covers (0 for pure additions).
    var oldRowCount: Int { oldEndLine - oldStartLine }
    /// Number of new-file lines this link covers (0 for pure deletions).
    var newRowCount: Int { newEndLine - newStartLine }

    /// Walks each hunk in `fileDiff`, grouping consecutive deletion/addition runs
    /// into a single link. Pure deletions and pure additions get a collapsed
    /// (zero-width) range on the opposite side.
    static func compute(fileDiff: FileDiff) -> [ConnectorLink] {
        var links: [ConnectorLink] = []
        for hunk in fileDiff.hunks {
            var oldLine = hunk.leftStartLine
            var newLine = hunk.rightStartLine
            var i = 0
            let lines = hunk.lines
            while i < lines.count {
                switch lines[i].type {
                case .context:
                    oldLine += 1
                    newLine += 1
                    i += 1

                case .deletion, .addition:
                    let oldStart = oldLine
                    let newStart = newLine
                    // Collapse a single contiguous run of deletions and additions
                    // (in any order, possibly interleaved) into one link, so the
                    // connector renders as a single ribbon for the whole edit.
                    while i < lines.count {
                        switch lines[i].type {
                        case .deletion: oldLine += 1; i += 1
                        case .addition: newLine += 1; i += 1
                        default:        break
                        }
                        if i < lines.count, lines[i].type != .deletion, lines[i].type != .addition {
                            break
                        }
                        if i >= lines.count { break }
                    }
                    let hasDel = oldLine > oldStart
                    let hasAdd = newLine > newStart
                    let kind: Kind
                    if hasDel && hasAdd { kind = .modification }
                    else if hasAdd      { kind = .addition }
                    else                { kind = .deletion }
                    links.append(ConnectorLink(
                        oldStartLine: oldStart, oldEndLine: oldLine,
                        newStartLine: newStart, newEndLine: newLine,
                        kind: kind
                    ))

                case .empty, .modification:
                    // Display-only types — not produced by the diff parser.
                    i += 1
                }
            }
        }
        return links
    }
}

// MARK: - Change Region

/// A contiguous run of rows in an aligned side-by-side view where at least one
/// side has a change (addition, deletion, or modification). Used by the
/// connector ribbon view to render colored Bezier bands across the gap.
struct ChangeRegion: Equatable {
    enum Kind: Equatable {
        case addition       // new-only — left side is empty/padding
        case deletion       // old-only — right side is empty/padding
        case modification   // both sides have content (deletion paired with addition)
    }
    let startRow: Int   // inclusive 0-based row index in the aligned arrays
    let endRow: Int     // inclusive 0-based row index in the aligned arrays
    let kind: Kind

    /// Number of rows the region spans.
    var rowCount: Int { endRow - startRow + 1 }

    /// Computes contiguous change regions from a pair of aligned `[DisplayLine]`
    /// arrays produced by `DisplayLineBuilder.buildSideBySideLines(…)`.
    /// Hunk-header rows act as natural separators between regions.
    static func compute(left: [DisplayLine], right: [DisplayLine]) -> [ChangeRegion] {
        guard left.count == right.count, !left.isEmpty else { return [] }

        var regions: [ChangeRegion] = []
        var i = 0
        while i < left.count {
            let l = left[i], r = right[i]
            // Skip rows that are pure context on both sides or hunk headers.
            if (l.type == .context && r.type == .context) || l.isHunkHeader || r.isHunkHeader {
                i += 1
                continue
            }

            // Start of a change region — advance until we hit context-on-both / a header / end.
            let start = i
            var hasDeletion = false
            var hasAddition = false
            while i < left.count {
                let li = left[i], ri = right[i]
                if (li.type == .context && ri.type == .context) || li.isHunkHeader || ri.isHunkHeader {
                    break
                }
                if li.type == .deletion { hasDeletion = true }
                if ri.type == .addition { hasAddition = true }
                i += 1
            }
            let end = i - 1
            let kind: Kind
            if hasDeletion && hasAddition { kind = .modification }
            else if hasAddition           { kind = .addition }
            else                          { kind = .deletion }
            regions.append(ChangeRegion(startRow: start, endRow: end, kind: kind))
        }
        return regions
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
    /// - `modifiedLines`: line numbers that are part of a modification pair — these
    ///   are tagged `.modification` (rendered blue) instead of `highlightType`.
    /// - `inlineRangesMap`: optional per-line inline highlight ranges (line number → ranges)
    static func buildFullFileLines(content: String, changedLines: Set<Int>,
                                   highlightType: DiffLineType = .addition,
                                   modifiedLines: Set<Int> = [],
                                   inlineRangesMap: [Int: [NSRange]] = [:]) -> [DisplayLine] {
        let lines = content.components(separatedBy: "\n")
        return lines.enumerated().map { index, text in
            let lineNum = index + 1
            let type: DiffLineType
            if modifiedLines.contains(lineNum) {
                type = .modification
            } else if changedLines.contains(lineNum) {
                type = highlightType
            } else {
                type = .context
            }
            return DisplayLine(
                id: "file-\(lineNum)",
                lineNumber: lineNum,
                text: text,
                type: type,
                inlineRanges: inlineRangesMap[lineNum] ?? []
            )
        }
    }

    /// Returns the set of line numbers (per side) that are part of a modification
    /// pair — i.e. live within a `ConnectorLink` whose kind is `.modification`.
    /// Used by `buildFullFileLines` to render those lines with the
    /// `.modification` (blue) background instead of pure add/del red/green.
    static func modifiedLineNumbers(fileDiff: FileDiff, side: Side) -> Set<Int> {
        var modified = Set<Int>()
        for link in ConnectorLink.compute(fileDiff: fileDiff) where link.kind == .modification {
            let range: Range<Int>
            switch side {
            case .left:  range = link.oldStartLine..<link.oldEndLine
            case .right: range = link.newStartLine..<link.newEndLine
            }
            for n in range { modified.insert(n) }
        }
        return modified
    }

    // MARK: - Aligned Side-by-Side

    /// Builds two equally-long `[DisplayLine]` arrays for side-by-side diff display.
    /// Blank/empty placeholder rows are inserted on the side that has fewer lines so
    /// that corresponding old/new lines always sit at the same vertical offset.
    /// This keeps the two panes visually aligned no matter how many additions/deletions
    /// have accumulated above the current scroll position.
    ///
    /// - `oldContent` / `newContent`: full file contents (post-fetch) for each side.
    /// - `fileDiff`: parsed unified diff used to locate hunks.
    /// - `oldInlineRanges` / `newInlineRanges`: per-line inline-change highlights
    ///   (use `inlineRangesMap(fileDiff:)` to compute these).
    static func buildSideBySideLines(
        oldContent: String,
        newContent: String,
        fileDiff: FileDiff,
        oldInlineRanges: [Int: [NSRange]] = [:],
        newInlineRanges: [Int: [NSRange]] = [:]
    ) -> (old: [DisplayLine], new: [DisplayLine]) {
        let oldLines = oldContent.isEmpty ? [] : oldContent.components(separatedBy: "\n")
        let newLines = newContent.isEmpty ? [] : newContent.components(separatedBy: "\n")

        var resultOld: [DisplayLine] = []
        var resultNew: [DisplayLine] = []
        var padCounter = 0
        var o = 1   // next 1-indexed old line to emit
        var n = 1   // next 1-indexed new line to emit

        func oldText(_ num: Int) -> String {
            (num >= 1 && num <= oldLines.count) ? oldLines[num - 1] : ""
        }
        func newText(_ num: Int) -> String {
            (num >= 1 && num <= newLines.count) ? newLines[num - 1] : ""
        }

        func emitContextPair() {
            resultOld.append(DisplayLine(
                id: "old-\(o)", lineNumber: o, text: oldText(o), type: .context
            ))
            resultNew.append(DisplayLine(
                id: "file-\(n)", lineNumber: n, text: newText(n), type: .context
            ))
            o += 1; n += 1
        }

        func emitOldOnly() {
            resultOld.append(DisplayLine(
                id: "old-\(o)", lineNumber: o, text: oldText(o), type: .deletion
            ))
            padCounter += 1
            resultNew.append(DisplayLine(
                id: "pad-new-\(padCounter)", lineNumber: nil, text: "", type: .empty
            ))
            o += 1
        }

        func emitNewOnly() {
            resultNew.append(DisplayLine(
                id: "file-\(n)", lineNumber: n, text: newText(n), type: .addition
            ))
            padCounter += 1
            resultOld.append(DisplayLine(
                id: "pad-old-\(padCounter)", lineNumber: nil, text: "", type: .empty
            ))
            n += 1
        }

        func emitChangePair() {
            let oldRanges = oldInlineRanges[o] ?? []
            let newRanges = newInlineRanges[n] ?? []
            resultOld.append(DisplayLine(
                id: "old-\(o)", lineNumber: o, text: oldText(o), type: .deletion,
                inlineRanges: oldRanges
            ))
            resultNew.append(DisplayLine(
                id: "file-\(n)", lineNumber: n, text: newText(n), type: .addition,
                inlineRanges: newRanges
            ))
            o += 1; n += 1
        }

        // Walk hunks in order of their position in the new file.
        let hunks = fileDiff.hunks.sorted { $0.rightStartLine < $1.rightStartLine }

        for hunk in hunks {
            // 1. Emit unchanged region from current (o, n) up to the hunk start.
            //    Hunk start lines are 1-indexed for the FIRST line of the hunk
            //    (which is typically a context line).
            while n < hunk.rightStartLine && o < hunk.leftStartLine
                  && o <= oldLines.count && n <= newLines.count {
                emitContextPair()
            }

            // 2. Walk this hunk's lines, emitting aligned pairs.
            var i = 0
            let lines = hunk.lines
            while i < lines.count {
                switch lines[i].type {
                case .context:
                    if o <= oldLines.count && n <= newLines.count {
                        emitContextPair()
                    } else {
                        // Defensive: keep counters in sync with hunk if file content is short.
                        o += 1; n += 1
                    }
                    i += 1

                case .deletion, .addition:
                    var deletions = 0
                    while i < lines.count && lines[i].type == .deletion {
                        deletions += 1; i += 1
                    }
                    var additions = 0
                    while i < lines.count && lines[i].type == .addition {
                        additions += 1; i += 1
                    }
                    let pairs = min(deletions, additions)
                    // Modification pairs (deletion ↔ addition).
                    for _ in 0..<pairs { emitChangePair() }
                    // Pure deletions — new side gets empty padding rows.
                    for _ in pairs..<deletions { emitOldOnly() }
                    // Pure additions — old side gets empty padding rows.
                    for _ in pairs..<additions { emitNewOnly() }

                case .empty, .modification:
                    // Display-only types — not produced by the diff parser.
                    i += 1
                }
            }
        }

        // 3. Trailing unchanged content after the last hunk.
        while o <= oldLines.count && n <= newLines.count {
            emitContextPair()
        }
        while o <= oldLines.count { emitOldOnly() }
        while n <= newLines.count { emitNewOnly() }

        return (resultOld, resultNew)
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
                case .empty, .modification:
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
