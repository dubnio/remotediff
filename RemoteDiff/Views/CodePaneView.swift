import SwiftUI
import AppKit

// MARK: - Line Height

/// Fixed line height used by both the NSTextView and the scroll anchor overlay.
/// Kept in sync via NSParagraphStyle.minimumLineHeight/maximumLineHeight.
let codeLineHeight: CGFloat = 20

// MARK: - Code Pane View

/// A unified view that renders a list of DisplayLines with line numbers,
/// type indicators, background highlighting, and syntax coloring.
/// Always rendered inline — the caller provides the ScrollView.
///
/// Uses NSTextView (via NSViewRepresentable) for proper multi-line text selection,
/// with an invisible anchor overlay for ScrollViewReader.scrollTo() support.
struct CodePaneView: View {
    let lines: [DisplayLine]
    let label: String?
    let language: LanguageConfig?
    let theme: SyntaxTheme
    /// Line numbers after which a thin deletion marker line should be drawn.
    /// Used in Side by Side / Full File modes to show where content was removed.
    let deletionMarkerAfterLines: Set<Int>

    init(lines: [DisplayLine], label: String? = nil, language: LanguageConfig? = nil,
         theme: SyntaxTheme = .xcodeDefault, deletionMarkerAfterLines: Set<Int> = []) {
        self.lines = lines
        self.label = label
        self.language = language
        self.theme = theme
        self.deletionMarkerAfterLines = deletionMarkerAfterLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(label == "Old" ? .red : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
            }

            ZStack(alignment: .topLeading) {
                // NSTextView — selectable text with syntax highlighting + line backgrounds
                SelectableCodeView(
                    attributedString: buildAttributedString(),
                    lineCount: lines.count,
                    backgroundColor: nsColor(theme.editorBackground)
                )

                // Invisible scroll anchors for ScrollViewReader.scrollTo()
                LazyVStack(spacing: 0) {
                    ForEach(lines) { line in
                        Color.clear
                            .frame(height: codeLineHeight)
                            .id(line.id)
                    }
                }
                .padding(.top, 2) // match textContainerInset
                .allowsHitTesting(false)

                // Deletion marker lines — thin red lines showing where content was removed
                if !deletionMarkerAfterLines.isEmpty {
                    deletionMarkers
                }
            }
        }
    }

    /// Thin red horizontal lines drawn after specific source lines to indicate removed content.
    private var deletionMarkers: some View {
        let markerColor = Color(nsColor: nsColor(theme.deletionBackground))
        // Build Y offsets: textContainerInset (2pt) + lineNumber * lineHeight
        let offsets: [CGFloat] = deletionMarkerAfterLines.sorted().compactMap { lineNum in
            // lineNum is 1-indexed source line; find its display index
            guard let idx = lines.firstIndex(where: { $0.lineNumber == lineNum }) else {
                // lineNum == 0 means "before the first line"
                if lineNum == 0 { return CGFloat(2) }
                return nil
            }
            return CGFloat(2) + CGFloat(idx + 1) * codeLineHeight
        }
        return ForEach(offsets, id: \.self) { y in
            Rectangle()
                .fill(markerColor)
                .frame(height: 2)
                .offset(y: y - 1) // center the 2px line on the boundary
        }
        .allowsHitTesting(false)
    }

    // MARK: - Attributed String Builder

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let gutterFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let codeFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.minimumLineHeight = codeLineHeight
        paraStyle.maximumLineHeight = codeLineHeight
        paraStyle.paragraphSpacing = 0
        paraStyle.paragraphSpacingBefore = 0

        // Multi-line carry-over state for block comments and triple-quoted strings.
        var inBlockComment = false
        var inTripleString: String? = nil

        for (i, line) in lines.enumerated() {
            let lineAttr = NSMutableAttributedString()

            if line.isHunkHeader {
                lineAttr.append(NSAttributedString(string: line.text, attributes: [
                    .font: gutterFont,
                    .foregroundColor: nsColor(theme.hunkHeaderText),
                    .paragraphStyle: paraStyle,
                ]))
            } else {
                // Line number
                let numStr = line.lineNumber.map { String(format: "%4d", $0) } ?? "    "
                lineAttr.append(NSAttributedString(string: numStr + " ", attributes: [
                    .font: gutterFont,
                    .foregroundColor: nsColor(theme.gutterText),
                    .paragraphStyle: paraStyle,
                ]))

                // Indicator (use ~ for modified lines with inline changes)
                let ind = !line.inlineRanges.isEmpty ? "~" : indicator(for: line.type)
                lineAttr.append(NSAttributedString(string: ind + " ", attributes: [
                    .font: gutterFont,
                    .foregroundColor: nsIndicatorColor(for: line.type),
                    .paragraphStyle: paraStyle,
                ]))

                // Syntax-highlighted code (with multi-line state tracking)
                let newState = appendHighlightedCode(
                    line.text, to: lineAttr, font: codeFont, paraStyle: paraStyle,
                    inBlockComment: inBlockComment, inTripleString: inTripleString
                )
                inBlockComment = newState.inBlockComment
                inTripleString = newState.inTripleString
            }

            // Append newline (except last line) BEFORE applying background
            // so the \n inherits the line's background color and eliminates gaps
            if i < lines.count - 1 {
                lineAttr.append(NSAttributedString(string: "\n", attributes: [
                    .font: codeFont, .paragraphStyle: paraStyle,
                ]))
            }

            // Apply full-line background (covers content + trailing \n)
            if line.isHunkHeader {
                lineAttr.addAttribute(.backgroundColor, value: nsColor(theme.hunkHeaderBackground),
                                      range: NSRange(location: 0, length: lineAttr.length))
            } else if let bg = nsLineBackground(for: line.type) {
                lineAttr.addAttribute(.backgroundColor, value: bg,
                                      range: NSRange(location: 0, length: lineAttr.length))
            }

            // Apply inline change highlights on top of line background
            if !line.inlineRanges.isEmpty && !line.isHunkHeader {
                let inlineBg: NSColor
                switch line.type {
                case .deletion:     inlineBg = nsColor(theme.inlineDeletionBackground)
                case .modification: inlineBg = nsColor(theme.inlineModificationBackground)
                default:            inlineBg = nsColor(theme.inlineAdditionBackground)
                }
                // Gutter prefix: "NNNN " (5) + "~ " (2) = 7 characters
                let gutterLen = 7
                for range in line.inlineRanges {
                    let adjusted = NSRange(location: range.location + gutterLen, length: range.length)
                    if adjusted.location + adjusted.length <= lineAttr.length {
                        lineAttr.addAttribute(.backgroundColor, value: inlineBg, range: adjusted)
                    }
                }
            }

            result.append(lineAttr)
        }

        return result
    }

    /// Appends syntax-highlighted code for a single line, threading multi-line state
    /// (block comments, triple-quoted strings) through. Returns the post-line state.
    private func appendHighlightedCode(
        _ text: String, to result: NSMutableAttributedString,
        font: NSFont, paraStyle: NSParagraphStyle,
        inBlockComment: Bool, inTripleString: String?
    ) -> (inBlockComment: Bool, inTripleString: String?) {
        guard let language = language, !text.isEmpty else {
            result.append(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: nsColor(theme.plain), .paragraphStyle: paraStyle,
            ]))
            return (inBlockComment, inTripleString)
        }

        let tokenizeResult = SyntaxHighlighter.tokenizeWithState(
            line: text, language: language,
            inBlockComment: inBlockComment, inTripleString: inTripleString
        )
        let tokens = tokenizeResult.tokens
        guard !tokens.isEmpty else {
            result.append(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: nsColor(theme.plain), .paragraphStyle: paraStyle,
            ]))
            return (tokenizeResult.inBlockComment, tokenizeResult.inTripleString)
        }

        for token in tokens {
            result.append(NSAttributedString(string: token.text, attributes: [
                .font: font,
                .foregroundColor: nsColor(theme.color(for: token.kind)),
                .paragraphStyle: paraStyle,
            ]))
        }
        return (tokenizeResult.inBlockComment, tokenizeResult.inTripleString)
    }

    // MARK: - NSColor Helpers

    private func nsColor(_ hex: HexColor) -> NSColor {
        NSColor(red: hex.red, green: hex.green, blue: hex.blue, alpha: hex.alpha)
    }

    private func nsIndicatorColor(for type: DiffLineType) -> NSColor {
        switch type {
        case .addition:     return .systemGreen
        case .deletion:     return .systemRed
        case .modification: return .systemBlue
        default:            return nsColor(theme.gutterText).withAlphaComponent(0.5)
        }
    }

    private func nsLineBackground(for type: DiffLineType) -> NSColor? {
        switch type {
        case .addition:     return nsColor(theme.additionBackground)
        case .deletion:     return nsColor(theme.deletionBackground)
        case .modification: return nsColor(theme.modificationBackground)
        case .empty:        return nsColor(theme.editorBackground).withAlphaComponent(0.5)
        case .context:      return nil
        }
    }

    private func indicator(for type: DiffLineType) -> String {
        switch type {
        case .addition:     return "+"
        case .deletion:     return "-"
        case .modification: return "~"
        default:            return " "
        }
    }
}

// MARK: - Selectable Code View (NSViewRepresentable)

/// Wraps an NSTextView for proper multi-line text selection with attributed string content.
/// Sizes to its content — no internal scrolling. The parent SwiftUI ScrollView handles scrolling.
private struct SelectableCodeView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let lineCount: Int
    let backgroundColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        // Custom layout manager that disables font leading to eliminate inter-line gaps
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = false

        let textContainer = NSTextContainer()
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 2)

        // No line wrapping — code extends beyond visible area, clipped by frame
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        // Only update text storage when content actually changed.
        // Since the NSTextView lives inside a SwiftUI ScrollView (not NSScrollView),
        // scroll position is preserved at the SwiftUI level as long as view identity is stable.
        if textView.string != attributedString.string {
            textView.textStorage?.setAttributedString(attributedString)
        }
        textView.backgroundColor = backgroundColor
    }

    /// Reports content size to SwiftUI so the parent ScrollView knows the scrollable area.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        let contentHeight = max(CGFloat(lineCount) * codeLineHeight, codeLineHeight)
        let height = contentHeight + 4 // textContainerInset top (2) + bottom (2)
        return CGSize(width: width, height: height)
    }
}
