import SwiftUI

// MARK: - Code Pane View

/// A unified view that renders a list of DisplayLines with line numbers,
/// type indicators, and background highlighting. Used for all view modes.
struct CodePaneView: View {
    let lines: [DisplayLine]
    let label: String?

    init(lines: [DisplayLine], label: String? = nil) {
        self.lines = lines
        self.label = label
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        if line.isHunkHeader {
                            hunkHeaderRow(line)
                        } else {
                            codeRow(line)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func hunkHeaderRow(_ line: DisplayLine) -> some View {
        Text(line.text)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.06))
    }

    @ViewBuilder
    private func codeRow(_ line: DisplayLine) -> some View {
        HStack(spacing: 0) {
            // Line number gutter
            Text(line.lineNumber.map { String(format: "%4d", $0) } ?? "    ")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 4)

            // Type indicator
            Text(indicator(for: line.type))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(indicatorColor(for: line.type))
                .frame(width: 14)

            // Code text
            Text(line.text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(backgroundColor(for: line.type))
    }

    // MARK: - Styling

    private func indicator(for type: DiffLineType) -> String {
        switch type {
        case .addition: return "+"
        case .deletion: return "-"
        default: return " "
        }
    }

    private func indicatorColor(for type: DiffLineType) -> Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        default: return .secondary.opacity(0.3)
        }
    }

    private func backgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .addition: return .green.opacity(0.1)
        case .deletion: return .red.opacity(0.1)
        case .empty: return .secondary.opacity(0.03)
        case .context: return .clear
        }
    }
}
