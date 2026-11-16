import SwiftUI
import AppKit

// MARK: - Error Message View

/// One-line error summary with a Copy button and, when there is more to read, a "Details…" button
/// that opens the full text in a sheet. Use instead of a bare red `Text` with `lineLimit`.
/// The summary is the message's first line (`SSHService.failureMessage` puts one there).
struct ErrorMessageView: View {
    let message: String

    @State private var details: ErrorDetails?

    /// ssh stderr ends with "\r\n"; normalise line endings and drop trailing
    /// blank lines so they don't render as empty rows or land on the clipboard.
    static func displayText(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first line of the message: the one-line summary.
    static func summary(_ message: String) -> String {
        let text = displayText(message)
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return first.isEmpty ? "Error" : first
    }

    /// Everything after the summary line, or nil when the summary is the whole message.
    static func detailText(_ message: String) -> String? {
        let text = displayText(message)
        guard let newline = text.firstIndex(of: "\n") else { return nil }
        let rest = text[text.index(after: newline)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
                .accessibilityLabel("Error")

            Text(Self.summary(message))
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if Self.detailText(message) != nil {
                DetailsButton { details = ErrorDetails(message: message) }
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
        .sheet(item: $details) { ErrorDetailsSheet(message: $0.message) }
    }
}

// MARK: - Error Details

/// The message a details sheet shows, captured when the user opens it, so a later fetch that
/// changes or clears the error doesn't change or close the sheet under the reader.
struct ErrorDetails: Identifiable {
    let id = UUID()
    let message: String
}

/// Borderless "Details…" button used next to an error summary.
struct DetailsButton: View {
    let action: () -> Void

    var body: some View {
        Button("Details…", action: action)
            .buttonStyle(.borderless)
            .font(.caption)
            .accessibilityHint("Shows the full error message")
    }
}

/// Modal with the full, selectable error text and a Copy button. Return and Escape close it.
struct ErrorDetailsSheet: View {
    let message: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var generation = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ErrorMessageView.summary(message))
                .font(.headline)
                .textSelection(.enabled)

            // Vertical only, so long hint paragraphs wrap instead of needing a horizontal scroll.
            ScrollView(.vertical) {
                Text(ErrorMessageView.detailText(message) ?? ErrorMessageView.displayText(message))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)

            HStack {
                Button(copied ? "Copied" : "Copy") {
                    CopyButton.copyToPasteboard(ErrorMessageView.displayText(message))
                    copied = true
                    generation += 1
                    let current = generation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if generation == current { copied = false }
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 640, height: 420)
        .onExitCommand { dismiss() }
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
