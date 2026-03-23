import Foundation

// MARK: - Diff Line Types

enum DiffLineType: Equatable {
    case context
    case addition
    case deletion
    case empty
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
    let id = UUID()
    let oldPath: String
    let newPath: String
    let isBinary: Bool
    let hunks: [DiffHunk]

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

        case .empty:
            i += 1
        }
    }

    return result
}
