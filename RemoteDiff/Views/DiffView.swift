import SwiftUI

// MARK: - View Mode

enum DiffViewMode: String, CaseIterable {
    case sideBySide = "Side by Side"
    case diff = "Diff"
    case fullFile = "Full File"

    var icon: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .diff: return "arrow.left.arrow.right"
        case .fullFile: return "doc.text"
        }
    }
}

// MARK: - Diff View

struct DiffView: View {
    let fileDiff: FileDiff?
    let host: String
    let repoPath: String
    let gitRef: String
    @Binding var viewMode: DiffViewMode
    @ObservedObject var fileContentService: FileContentService

    var body: some View {
        Group {
            if let fileDiff = fileDiff {
                if fileDiff.isBinary {
                    placeholder(icon: "doc.zipper", title: "Binary File",
                                subtitle: fileDiff.displayName, color: .orange)
                } else if fileDiff.hunks.isEmpty && fileDiff.isNewFile {
                    placeholder(icon: "doc.badge.plus", title: "New Empty File",
                                subtitle: fileDiff.displayName, color: .green)
                } else if fileDiff.hunks.isEmpty {
                    placeholder(icon: "checkmark.circle", title: "No Changes", color: .green)
                } else {
                    mainContent(fileDiff)
                }
            } else {
                placeholder(icon: "doc.text.magnifyingglass", title: "Select a file", color: .secondary)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(_ fileDiff: FileDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader(fileDiff)

            ZStack {
                // Diff mode — always rendered, shown/hidden
                diffModeContent(fileDiff)
                    .opacity(viewMode == .diff ? 1 : 0)
                    .allowsHitTesting(viewMode == .diff)

                // Full file / Side by side — rendered on demand
                if viewMode != .diff {
                    fileContentModeView(fileDiff)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Diff Mode

    @ViewBuilder
    private func diffModeContent(_ fileDiff: FileDiff) -> some View {
        let leftLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)
        let rightLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .right)

        GeometryReader { geo in
            HStack(spacing: 0) {
                CodePaneView(lines: leftLines)
                    .frame(width: geo.size.width / 2)

                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)

                CodePaneView(lines: rightLines)
                    .frame(width: geo.size.width / 2)
            }
        }
    }

    // MARK: - File Content Mode (Full File / Side by Side)

    @ViewBuilder
    private func fileContentModeView(_ fileDiff: FileDiff) -> some View {
        let isCurrent = fileContentService.lastFileID == fileDiff.id

        if !isCurrent || fileContentService.isLoading {
            VStack { Spacer(); ProgressView("Loading file…"); Spacer() }
                .frame(maxWidth: .infinity)
        } else if let error = fileContentService.loadError {
            VStack(spacing: 8) {
                Spacer()
                Text("Failed to load file").foregroundColor(.secondary)
                Text(error).font(.caption).foregroundColor(.red)
                Button("Retry") {
                    fileContentService.fetchFor(fileDiff: fileDiff, host: host, repoPath: repoPath, gitRef: gitRef)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if fileContentService.newContent != nil {
            if viewMode == .fullFile {
                fullFileContent(fileDiff)
            } else {
                sideBySideContent(fileDiff)
            }
        } else {
            VStack { Spacer(); ProgressView("Loading file…"); Spacer() }
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func fullFileContent(_ fileDiff: FileDiff) -> some View {
        let addedLines = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .addition)
        let lines = DisplayLineBuilder.buildFullFileLines(
            content: fileContentService.newContent ?? "", changedLines: addedLines
        )
        CodePaneView(lines: lines)
    }

    @ViewBuilder
    private func sideBySideContent(_ fileDiff: FileDiff) -> some View {
        let deletedLines = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .deletion)
        let addedLines = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .addition)
        let oldLines = DisplayLineBuilder.buildFullFileLines(
            content: fileContentService.oldContent ?? "", changedLines: deletedLines
        )
        let newLines = DisplayLineBuilder.buildFullFileLines(
            content: fileContentService.newContent ?? "", changedLines: addedLines
        )

        GeometryReader { geo in
            HStack(spacing: 0) {
                CodePaneView(lines: oldLines, label: "Old")
                    .frame(width: geo.size.width / 2)

                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)

                CodePaneView(lines: newLines, label: "New")
                    .frame(width: geo.size.width / 2)
            }
        }
    }

    // MARK: - File Header

    @ViewBuilder
    private func fileHeader(_ fileDiff: FileDiff) -> some View {
        HStack {
            if fileDiff.isNewFile {
                Label("New File", systemImage: "plus.circle.fill").foregroundColor(.green).font(.caption)
            } else if fileDiff.isDeletedFile {
                Label("Deleted", systemImage: "minus.circle.fill").foregroundColor(.red).font(.caption)
            } else if fileDiff.isRenamed {
                Label("Renamed", systemImage: "arrow.right.circle.fill").foregroundColor(.orange).font(.caption)
            }

            Text(fileDiff.displayName)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)

            Spacer()

            let stats = countStats(fileDiff)
            if stats.0 > 0 { Text("+\(stats.0)").foregroundColor(.green).font(.system(.caption, design: .monospaced)) }
            if stats.1 > 0 { Text("-\(stats.1)").foregroundColor(.red).font(.system(.caption, design: .monospaced)) }

            if !fileDiff.isBinary {
                Picker("", selection: $viewMode) {
                    ForEach(DiffViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    // MARK: - Placeholder

    private func placeholder(icon: String, title: String, subtitle: String? = nil, color: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 48)).foregroundColor(color.opacity(0.6))
            Text(title).font(.title2).foregroundColor(.secondary)
            if let subtitle {
                Text(subtitle).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countStats(_ fileDiff: FileDiff) -> (Int, Int) {
        var add = 0, del = 0
        for hunk in fileDiff.hunks { for line in hunk.lines {
            if line.type == .addition { add += 1 }
            if line.type == .deletion { del += 1 }
        }}
        return (add, del)
    }
}
