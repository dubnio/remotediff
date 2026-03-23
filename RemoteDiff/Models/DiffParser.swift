import Foundation

// MARK: - Diff Parser

struct DiffParser {
    /// Parses raw unified diff output (from `git diff`) into an array of FileDiff.
    static func parse(_ raw: String) -> [FileDiff] {
        let lines = raw.components(separatedBy: "\n")
        var fileDiffs: [FileDiff] = []
        var i = 0

        while i < lines.count {
            // Look for "diff --git a/... b/..."
            guard lines[i].hasPrefix("diff --git ") else {
                i += 1
                continue
            }

            let (fileDiff, nextIndex) = parseFileDiff(lines: lines, startIndex: i)
            if let fileDiff = fileDiff {
                fileDiffs.append(fileDiff)
            }
            i = nextIndex
        }

        return fileDiffs
    }

    // MARK: - Private

    private static func parseFileDiff(lines: [String], startIndex: Int) -> (FileDiff?, Int) {
        var i = startIndex
        let diffLine = lines[i]
        i += 1

        // Extract paths from "diff --git a/path b/path"
        let (aPath, bPath) = extractPaths(from: diffLine)

        // Skip index, mode, similarity lines; detect new/deleted file markers
        var isNewFileMode = false
        var isDeletedFileMode = false
        while i < lines.count &&
              !lines[i].hasPrefix("diff --git ") &&
              !lines[i].hasPrefix("--- ") &&
              !lines[i].hasPrefix("Binary files ") {
            if lines[i].hasPrefix("new file mode") { isNewFileMode = true }
            if lines[i].hasPrefix("deleted file mode") { isDeletedFileMode = true }
            i += 1
        }

        // Check for binary
        if i < lines.count && lines[i].hasPrefix("Binary files ") {
            i += 1
            return (FileDiff(oldPath: aPath, newPath: bPath, isBinary: true, hunks: []), i)
        }

        // Parse --- and +++ headers
        var oldPath = aPath
        var newPath = bPath

        if i < lines.count && lines[i].hasPrefix("--- ") {
            oldPath = extractFilePath(from: lines[i], prefix: "--- ")
            i += 1
        } else if isNewFileMode {
            oldPath = "/dev/null"
        }
        if i < lines.count && lines[i].hasPrefix("+++ ") {
            newPath = extractFilePath(from: lines[i], prefix: "+++ ")
            i += 1
        } else if isDeletedFileMode {
            newPath = "/dev/null"
        }

        // Parse hunks
        var hunks: [DiffHunk] = []
        while i < lines.count && !lines[i].hasPrefix("diff --git ") {
            if lines[i].hasPrefix("@@") {
                let (hunk, nextIndex) = parseHunk(lines: lines, startIndex: i)
                if let hunk = hunk {
                    hunks.append(hunk)
                }
                i = nextIndex
            } else {
                i += 1
            }
        }

        return (FileDiff(oldPath: oldPath, newPath: newPath, isBinary: false, hunks: hunks), i)
    }

    private static func parseHunk(lines: [String], startIndex: Int) -> (DiffHunk?, Int) {
        let header = lines[startIndex]
        var i = startIndex + 1

        // Parse "@@ -l,s +l,s @@" to get starting line numbers
        let (leftStart, rightStart) = parseHunkHeader(header)
        var leftLine = leftStart
        var rightLine = rightStart

        var diffLines: [DiffLine] = []

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("diff --git ") || line.hasPrefix("@@") {
                break
            }

            if line.hasPrefix("-") {
                diffLines.append(DiffLine(type: .deletion, text: String(line.dropFirst(1)), lineNumber: leftLine))
                leftLine += 1
            } else if line.hasPrefix("+") {
                diffLines.append(DiffLine(type: .addition, text: String(line.dropFirst(1)), lineNumber: rightLine))
                rightLine += 1
            } else if line.hasPrefix(" ") {
                diffLines.append(DiffLine(type: .context, text: String(line.dropFirst(1)), lineNumber: leftLine))
                leftLine += 1
                rightLine += 1
            } else if line == "\\ No newline at end of file" {
                // skip
            } else if line.isEmpty && i == lines.count - 1 {
                // trailing empty line at end of diff
                break
            } else {
                // Context line without leading space (some diffs)
                diffLines.append(DiffLine(type: .context, text: line, lineNumber: leftLine))
                leftLine += 1
                rightLine += 1
            }

            i += 1
        }

        let hunk = DiffHunk(header: header, leftStartLine: leftStart, rightStartLine: rightStart, lines: diffLines)
        return (hunk, i)
    }

    /// Parses "@@ -10,7 +10,8 @@ optional context" into (leftStart, rightStart)
    static func parseHunkHeader(_ header: String) -> (Int, Int) {
        // Pattern: @@ -LEFT,COUNT +RIGHT,COUNT @@
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let leftRange = Range(match.range(at: 1), in: header),
              let rightRange = Range(match.range(at: 2), in: header),
              let left = Int(header[leftRange]),
              let right = Int(header[rightRange]) else {
            return (1, 1)
        }
        return (left, right)
    }

    /// Extracts a/path and b/path from "diff --git a/path b/path"
    private static func extractPaths(from line: String) -> (String, String) {
        // Handle: diff --git a/file.txt b/file.txt
        let stripped = String(line.dropFirst("diff --git ".count))

        // Find the split point — "a/" at start and " b/" somewhere
        if let range = stripped.range(of: " b/") {
            let aPath = String(stripped[stripped.startIndex..<range.lowerBound])
                .replacingOccurrences(of: "a/", with: "", options: .anchored)
            let bPath = String(stripped[range.upperBound...])
            return (aPath, bPath)
        }

        return ("unknown", "unknown")
    }

    /// Extracts file path from "--- a/path" or "+++ b/path"
    private static func extractFilePath(from line: String, prefix: String) -> String {
        var path = String(line.dropFirst(prefix.count))
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        return path
    }
}
