import Foundation

// MARK: - Diff Line Types

enum DiffLineType: Equatable {
    case context
    case addition
    case deletion
    case empty
    /// A row that's part of a modification pair (a deletion paired with an
    /// addition, where the line was *changed* rather than purely added or
    /// removed). Rendered with a distinct color (typically blue) so the user
    /// can tell at a glance which lines are real additions/deletions vs
    /// edits to existing lines. Only set by display-line builders; the diff
    /// parser still produces .addition / .deletion / .context.
    case modification
}

// MARK: - DiffLine

struct DiffLine: Identifiable, Equatable {
    let id = UUID()
    let type: DiffLineType
    let text: String
    let lineNumber: Int?
}

// MARK: - DiffHunk

struct DiffHunk: Identifiable, Equatable {
    let id = UUID()
    let header: String
    let leftStartLine: Int
    let rightStartLine: Int
    let lines: [DiffLine]

    var pairedLines: [(left: DiffLine?, right: DiffLine?)] {
        pairLines(lines)
    }
}

// MARK: - FileDiff

struct FileDiff: Identifiable, Equatable {
    /// Deterministic ID based on file paths — same file keeps the same identity across refreshes.
    let id: String
    let oldPath: String
    let newPath: String
    let isBinary: Bool
    let hunks: [DiffHunk]

    init(oldPath: String, newPath: String, isBinary: Bool, hunks: [DiffHunk]) {
        self.id = "\(oldPath):\(newPath)"
        self.oldPath = oldPath
        self.newPath = newPath
        self.isBinary = isBinary
        self.hunks = hunks
    }

    var displayName: String {
        if oldPath == newPath || oldPath == "/dev/null" { return newPath }
        if newPath == "/dev/null" { return oldPath }
        return "\(oldPath) → \(newPath)"
    }

    var isNewFile: Bool { oldPath == "/dev/null" }
    var isDeletedFile: Bool { newPath == "/dev/null" }
    var isRenamed: Bool { oldPath != newPath && !isNewFile && !isDeletedFile }
}

// MARK: - SSHHost

struct SSHHost: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let hostname: String?
    let user: String?
    let port: Int?
    let identityFile: String?

    var displayName: String { name }
}

// MARK: - Repo Selection

struct RepoSelection: Equatable {
    var connectionID: UUID
    var repositoryID: UUID
}

// MARK: - Pair Lines

/// Pairs diff lines for side-by-side display.
/// Deletions pair with following additions; context lines appear on both sides.
func pairLines(_ lines: [DiffLine]) -> [(left: DiffLine?, right: DiffLine?)] {
    var result: [(left: DiffLine?, right: DiffLine?)] = []
    var i = 0

    while i < lines.count {
        switch lines[i].type {
        case .context:
            result.append((left: lines[i], right: lines[i]))
            i += 1

        case .deletion:
            var deletions: [DiffLine] = []
            while i < lines.count && lines[i].type == .deletion {
                deletions.append(lines[i]); i += 1
            }
            var additions: [DiffLine] = []
            while i < lines.count && lines[i].type == .addition {
                additions.append(lines[i]); i += 1
            }
            let padding = DiffLine(type: .empty, text: "", lineNumber: nil)
            for j in 0..<max(deletions.count, additions.count) {
                result.append((
                    left: j < deletions.count ? deletions[j] : padding,
                    right: j < additions.count ? additions[j] : padding
                ))
            }

        case .addition:
            result.append((left: DiffLine(type: .empty, text: "", lineNumber: nil), right: lines[i]))
            i += 1

        case .empty, .modification:
            // .modification is a display-only type; the parser never produces
            // it, so we just skip if it ever appears here.
            i += 1
        }
    }

    return result
}
