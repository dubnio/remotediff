import SwiftUI
import AppKit

// MARK: - Error Message View

/// Readable, selectable, copyable error box. Use instead of a bare red `Text` with `lineLimit`.
/// Hugs short messages; above 200 pt the text scrolls inside the box.
struct ErrorMessageView: View {
    let message: String

    static let maxHeight: CGFloat = 200

    /// ssh stderr ends with "\r\n"; normalise line endings and drop trailing
    /// blank lines so they don't render as empty rows or land on the clipboard.
    static func displayText(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var messageText: some View {
        Text(Self.displayText(message))
            .font(.caption)
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
                .accessibilityLabel("Error")

            CappedHeight(maxHeight: Self.maxHeight) {
                ViewThatFits(in: .vertical) {
                    messageText
                    ScrollView(.vertical) { messageText }
                }
            }

            CopyButton(text: Self.displayText(message))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Capped Height

/// Always offers its child `maxHeight` (whatever the parent offers) and reports
/// the child's own size. A plain `.frame(maxHeight:)` would instead grow to fill
/// the parent's offer, so short messages would get a 200 pt box.
private struct CappedHeight: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: maxHeight)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let text: String
    var help: String = "Copy error message"

    @State private var copied = false
    @State private var generation = 0

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    var body: some View {
        Button {
            Self.copyToPasteboard(text)
            copied = true
            generation += 1
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if generation == current { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(copied ? "Copied" : help)
        .onChange(of: text) { _ in
            generation += 1
            copied = false
        }
    }
}
