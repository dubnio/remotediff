import Foundation

// MARK: - Display Line

/// A unified line model for rendering in any view mode (diff, full file, side-by-side).
struct DisplayLine: Identifiable, Equatable {
    let id: String
    let lineNumber: Int?
    let text: String
    let type: DiffLineType
    let isHunkHeader: Bool

    init(id: String, lineNumber: Int? = nil, text: String, type: DiffLineType = .context, isHunkHeader: Bool = false) {
        self.id = id
        self.lineNumber = lineNumber
        self.text = text
        self.type = type
        self.isHunkHeader = isHunkHeader
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
                result.append(DisplayLine(
                    id: "hunk-\(hunkIdx)-line-\(pairIdx)",
                    lineNumber: line?.lineNumber,
                    text: line?.text ?? "",
                    type: line?.type ?? .empty
                ))
            }
        }

        return result
    }

    // MARK: - Full File Mode

    /// Builds display lines for a full file view, highlighting changed lines.
    static func buildFullFileLines(content: String, changedLines: Set<Int>) -> [DisplayLine] {
        let lines = content.components(separatedBy: "\n")
        return lines.enumerated().map { index, text in
            let lineNum = index + 1
            let type: DiffLineType = changedLines.contains(lineNum) ? .addition : .context
            return DisplayLine(
                id: "file-\(lineNum)",
                lineNumber: lineNum,
                text: text,
                type: type
            )
        }
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
