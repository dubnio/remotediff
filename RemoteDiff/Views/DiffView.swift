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
    let theme: SyntaxTheme
    @Binding var viewMode: DiffViewMode
    @ObservedObject var fileContentService: FileContentService

    @State private var scrollTarget: String = ""
    @State private var scrollTrigger: Int = 0
    @State private var currentChangeIdx: Int = -1

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
        .onChange(of: fileDiff?.id) { _ in
            currentChangeIdx = -1
            scheduleScrollToFirstChange()
        }
        .onChange(of: viewMode) { _ in
            currentChangeIdx = -1
            scheduleScrollToFirstChange()
        }
        // For file-content modes (Side by Side / Full File), anchors only exist once the
        // remote file content has been fetched. Trigger the auto-scroll when content arrives,
        // but only if we haven't already auto-scrolled (currentChangeIdx still -1).
        .onChange(of: fileContentService.newContent) { _ in
            if currentChangeIdx == -1 { scheduleScrollToFirstChange() }
        }
        .background {
            Button("") { navigateChange(direction: -1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .hidden()
            Button("") { navigateChange(direction: 1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .hidden()
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
        let lang = LanguageConfig.detect(from: fileDiff.newPath)
        let leftLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .left)
        let rightLines = DisplayLineBuilder.buildDiffLines(fileDiff: fileDiff, side: .right)
        // Diff mode pairs hunks already; no connector ribbons needed.
        dualPaneScroll(left: leftLines, right: rightLines,
                       language: lang, theme: theme)
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
        let lang = LanguageConfig.detect(from: fileDiff.newPath)
        let addedLines = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .addition)
        let modifiedLines = DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .right)
        let inlineMaps = DisplayLineBuilder.inlineRangesMap(fileDiff: fileDiff)
        let delMarkers = DisplayLineBuilder.deletionMarkerPositions(fileDiff: fileDiff)
        let lines = DisplayLineBuilder.buildFullFileLines(
            content: fileContentService.newContent ?? "", changedLines: addedLines,
            modifiedLines: modifiedLines,
            inlineRangesMap: inlineMaps.new
        )
        scrollableContent {
            CodePaneView(lines: lines, language: lang, theme: theme,
                         deletionMarkerAfterLines: delMarkers)
        }
    }

    @ViewBuilder
    private func sideBySideContent(_ fileDiff: FileDiff) -> some View {
        let lang = LanguageConfig.detect(from: fileDiff.newPath)
        let deletedLines = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .deletion)
        let addedLines = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .addition)
        let inlineMaps = DisplayLineBuilder.inlineRangesMap(fileDiff: fileDiff)
        // Each side renders its own raw, unpadded full-file content. The Bezier
        // connector ribbons in the gap visually link the changed regions on each
        // side — since the panes have different line counts, the ribbons swoop
        // diagonally to map deletions on the left to additions on the right.
        let oldModified = DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .left)
        let newModified = DisplayLineBuilder.modifiedLineNumbers(fileDiff: fileDiff, side: .right)
        let oldLines = DisplayLineBuilder.buildFullFileLines(
            content: fileContentService.oldContent ?? "",
            changedLines: deletedLines,
            highlightType: .deletion,
            modifiedLines: oldModified,
            inlineRangesMap: inlineMaps.old
        )
        let newLines = DisplayLineBuilder.buildFullFileLines(
            content: fileContentService.newContent ?? "",
            changedLines: addedLines,
            highlightType: .addition,
            modifiedLines: newModified,
            inlineRangesMap: inlineMaps.new
        )
        let links = ConnectorLink.compute(fileDiff: fileDiff)
        dualPaneScroll(left: oldLines, right: newLines,
                       leftLabel: "Old", rightLabel: "New",
                       language: lang, theme: theme,
                       connectorLinks: links)
    }

    // MARK: - Scrollable Content Helpers

    /// Wraps content in a ScrollView with ScrollViewReader for change navigation.
    @ViewBuilder
    private func scrollableContent<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
            }
            .onChange(of: scrollTrigger) { _ in
                withAnimation { proxy.scrollTo(scrollTarget, anchor: .top) }
            }
        }
    }

    /// Two side-by-side CodePaneViews in a synced ScrollView with GeometryReader.
    /// When `connectorLinks` is non-nil, a third pane is inserted in the middle
    /// that renders cubic-Bézier ribbons connecting the change regions on each
    /// (unaligned) side, scrolling in lock-step with the code panes.
    @ViewBuilder
    private func dualPaneScroll(
        left: [DisplayLine], right: [DisplayLine],
        leftLabel: String? = nil, rightLabel: String? = nil,
        language: LanguageConfig? = nil,
        theme: SyntaxTheme = .xcodeDefault,
        rightDeletionMarkers: Set<Int> = [],
        connectorLinks: [ConnectorLink]? = nil
    ) -> some View {
        GeometryReader { geo in
            let showConnectors = connectorLinks != nil
            let connectorWidth: CGFloat = showConnectors ? 28 : 1
            let paneWidth = max((geo.size.width - connectorWidth) / 2, 0)
            // When connectors are enabled we render labels in a separate band
            // above the HStack so the connector canvas and code panes share an
            // identical Y origin inside the ScrollView. Otherwise labels are
            // rendered inline by `CodePaneView` (legacy behaviour).
            let inlineLabels = !showConnectors
            VStack(spacing: 0) {
                if showConnectors && (leftLabel != nil || rightLabel != nil) {
                    paneLabelBand(leftLabel: leftLabel, rightLabel: rightLabel,
                                  paneWidth: paneWidth, gapWidth: connectorWidth)
                }
                scrollableContent {
                    HStack(alignment: .top, spacing: 0) {
                        CodePaneView(
                            lines: left,
                            label: inlineLabels ? leftLabel : nil,
                            language: language, theme: theme
                        )
                        .frame(width: paneWidth)

                        connectorPane(
                            links: connectorLinks,
                            leftCount: left.count, rightCount: right.count,
                            width: connectorWidth, theme: theme
                        )

                        CodePaneView(
                            lines: right,
                            label: inlineLabels ? rightLabel : nil,
                            language: language, theme: theme,
                            deletionMarkerAfterLines: rightDeletionMarkers
                        )
                        .frame(width: paneWidth)
                    }
                }
            }
        }
    }

    /// Single label band rendered above the synced `ScrollView` when connectors
    /// are enabled. Mirrors the styling that `CodePaneView` uses for inline labels.
    /// Pinned to a fixed height so the middle gap-spacer (which has no intrinsic
    /// height) cannot expand the band to fill the entire viewport.
    @ViewBuilder
    private func paneLabelBand(
        leftLabel: String?, rightLabel: String?,
        paneWidth: CGFloat, gapWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            paneLabel(leftLabel, color: .red)
                .frame(width: paneWidth, alignment: .leading)
            Color.clear.frame(width: gapWidth)
            paneLabel(rightLabel, color: .green)
                .frame(width: paneWidth, alignment: .leading)
        }
        .frame(height: paneLabelBandHeight)
        .background(Color.secondary.opacity(0.05))
    }

    @ViewBuilder
    private func paneLabel(_ text: String?, color: Color) -> some View {
        if let text {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
                .padding(.horizontal, 8)
        } else {
            Color.clear
        }
    }

    private var paneLabelBandHeight: CGFloat { 22 }

    /// Renders the gap between the two code panes — either a thin divider line
    /// (when no connector links are provided) or a wider canvas drawing Bézier
    /// connector ribbons that swoop between the unaligned panes.
    @ViewBuilder
    private func connectorPane(
        links: [ConnectorLink]?,
        leftCount: Int, rightCount: Int,
        width: CGFloat, theme: SyntaxTheme
    ) -> some View {
        if let links {
            ConnectorRibbonsView(
                links: links,
                lineHeight: codeLineHeight,
                theme: theme,
                width: width,
                totalHeight: CGFloat(max(leftCount, rightCount)) * codeLineHeight + 4
            )
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: width)
        }
    }

    // MARK: - File Header

    @ViewBuilder
    private func fileHeader(_ fileDiff: FileDiff) -> some View {
        let anchors = changeAnchors(for: fileDiff)

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

            // Change navigation
            if !anchors.isEmpty {
                HStack(spacing: 4) {
                    Button { navigateChange(direction: -1) } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentChangeIdx <= 0)

                    Text("\(max(currentChangeIdx + 1, 1))/\(anchors.count)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 36)

                    Button { navigateChange(direction: 1) } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentChangeIdx >= anchors.count - 1)
                }
            }

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

    // MARK: - Change Navigation

    private func changeAnchors(for fileDiff: FileDiff) -> [String] {
        if viewMode == .diff {
            return (0..<fileDiff.hunks.count).map { "hunk-\($0)" }
        }
        // For file-based views, group consecutive changed line numbers.
        // Side-by-side includes both additions (new file) and deletions (old file).
        let additions = DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .addition)
        let changed = viewMode == .sideBySide
            ? additions.union(DisplayLineBuilder.changedLineNumbers(fileDiff: fileDiff, type: .deletion))
            : additions
        let sorted = changed.sorted()
        var anchors: [String] = []
        var prev = -2
        for num in sorted {
            if num != prev + 1 { anchors.append("file-\(num)") }
            prev = num
        }
        return anchors
    }

    private func navigateChange(direction: Int) {
        guard let fileDiff = fileDiff else { return }
        let anchors = changeAnchors(for: fileDiff)
        guard !anchors.isEmpty else { return }
        let newIdx = min(max(0, currentChangeIdx + direction), anchors.count - 1)
        currentChangeIdx = newIdx
        scrollTarget = anchors[newIdx]
        scrollTrigger += 1
    }

    /// Schedules an auto-scroll to the first change in the current file after a short
    /// delay so SwiftUI can lay out the anchor `.id()`s before `scrollTo` fires.
    /// No-op when the file has no changes or, for file-content modes, when content
    /// hasn't been fetched yet (we'll be re-invoked by the newContent onChange).
    private func scheduleScrollToFirstChange() {
        guard let fileDiff = fileDiff else { return }
        let anchors = changeAnchors(for: fileDiff)
        guard !anchors.isEmpty else { return }

        // For file-content modes, wait until content is loaded — otherwise the
        // anchor IDs aren't in the rendered hierarchy yet.
        if viewMode != .diff && fileContentService.newContent == nil { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Re-check that selection / mode haven't changed under us by recomputing.
            guard let current = self.fileDiff else { return }
            let currentAnchors = self.changeAnchors(for: current)
            guard let first = currentAnchors.first else { return }
            self.currentChangeIdx = 0
            self.scrollTarget = first
            self.scrollTrigger += 1
        }
    }
}
