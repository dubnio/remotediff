import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var themeStore: ThemeStore

    var body: some View {
        TabView {
            ThemeSettingsView(themeStore: themeStore)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            CLISettingsView()
                .tabItem {
                    Label("CLI", systemImage: "terminal")
                }

            KeyboardShortcutsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 580, height: 460)
    }
}

// MARK: - Theme Settings

struct ThemeSettingsView: View {
    @ObservedObject var themeStore: ThemeStore
    @State private var previewTheme: SyntaxTheme?

    private var displayTheme: SyntaxTheme {
        previewTheme ?? themeStore.currentTheme
    }

    var body: some View {
        VStack(spacing: 0) {
            // Theme picker
            HStack {
                Text("Syntax Theme")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Theme grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SyntaxTheme.allThemes) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: themeStore.currentTheme.id == theme.id
                        ) {
                            themeStore.select(theme)
                            previewTheme = nil
                        }
                        .onHover { hovering in
                            previewTheme = hovering ? theme : nil
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 12)

            Divider()

            // Live preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Preview")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if previewTheme != nil {
                        Text("— hovering: \(displayTheme.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(displayTheme.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.1))
                        )
                }
                .padding(.horizontal)
                .padding(.top, 10)

                ThemePreview(theme: displayTheme)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }

            Spacer()
        }
    }
}

// MARK: - Theme Card

struct ThemeCard: View {
    let theme: SyntaxTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            // Mini color swatch
            HStack(spacing: 2) {
                colorStripe(theme.keyword.color)
                colorStripe(theme.string.color)
                colorStripe(theme.type.color)
                colorStripe(theme.comment.color)
                colorStripe(theme.number.color)
            }
            .frame(width: 74, height: 36)
            .background(theme.editorBackground.color)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(theme.name)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private func colorStripe(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 12, height: 28)
    }
}

// MARK: - Theme Preview

struct ThemePreview: View {
    let theme: SyntaxTheme

    private let previewCode: [(String, SyntaxTokenKind)] = [
        ("import", .keyword), (" Foundation\n", .plain),
        ("\n", .plain),
        ("/// A sample class", .comment), ("\n", .plain),
        ("class", .keyword), (" ", .plain), ("Greeter", .type), (" {\n", .plain),
        ("    ", .plain), ("let", .keyword), (" name: ", .plain), ("String", .type), ("\n", .plain),
        ("    ", .plain), ("let", .keyword), (" count = ", .plain), ("42", .number), ("\n", .plain),
        ("\n", .plain),
        ("    ", .plain), ("func", .keyword), (" greet() -> ", .plain), ("String", .type), (" {\n", .plain),
        ("        ", .plain), ("return", .keyword), (" ", .plain), ("\"Hello, \\(name)!\"", .string), ("\n", .plain),
        ("    }\n", .plain),
        ("}\n", .plain),
        ("\n", .plain),
        ("let", .keyword), (" isReady = ", .plain), ("true", .literal), ("\n", .plain),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewLines
        }
        .padding(10)
        .background(theme.editorBackground.color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var previewLines: some View {
        let text = buildPreviewText()
        return text
            .font(.system(.caption, design: .monospaced))
            .lineLimit(nil)
    }

    private func buildPreviewText() -> Text {
        var result = Text("")
        for (str, kind) in previewCode {
            result = result + Text(str).foregroundColor(theme.color(for: kind).color)
        }
        return result
    }
}

// MARK: - CLI Settings View

struct CLISettingsView: View {
    @State private var cliStatus: CLIStatus = .checking

    enum CLIStatus: Equatable {
        case checking
        case installed(path: String, target: String)
        case notInstalled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Command Line Interface")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Text("Open remote repositories from the terminal, similar to `code` for VS Code.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 16)

            // Status card
            statusCard
                .padding(.horizontal)
                .padding(.bottom, 16)

            // Install instructions
            installInstructions
                .padding(.horizontal)
                .padding(.bottom, 16)

            Divider()
                .padding(.horizontal)
                .padding(.bottom, 12)

            // Usage examples
            usageExamples
                .padding(.horizontal)

            Spacer()
        }
        .onAppear { checkCLIStatus() }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(.body).weight(.medium))

                Text(statusDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                checkCLIStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Refresh status")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var statusIcon: String {
        switch cliStatus {
        case .checking: return "circle.dotted"
        case .installed: return "checkmark.circle.fill"
        case .notInstalled: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch cliStatus {
        case .checking: return .secondary
        case .installed: return .green
        case .notInstalled: return .red
        }
    }

    private var statusTitle: String {
        switch cliStatus {
        case .checking: return "Checking…"
        case .installed: return "CLI Installed"
        case .notInstalled: return "CLI Not Installed"
        }
    }

    private var statusDetail: String {
        switch cliStatus {
        case .checking:
            return "Looking for remotediff in PATH…"
        case .installed(let path, let target):
            return "\(path) → \(target)"
        case .notInstalled:
            return "The remotediff command is not available in your PATH."
        }
    }

    // MARK: - Install Instructions

    private var installInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch cliStatus {
            case .installed:
                Text("To reinstall or update, run:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            case .notInstalled, .checking:
                Text("To install, run this in your terminal:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            let command = installCommand
            HStack(spacing: 0) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Copy to clipboard")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private var installCommand: String {
        // Try to find the script bundled with the running app first
        if let bundledPath = Bundle.main.path(forResource: "remotediff", ofType: nil) {
            return "sudo ln -sf '\(bundledPath)' /usr/local/bin/remotediff"
        }
        // Fallback: use the scripts/ directory relative to the executable
        let execURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/remotediff")
        if let path = execURL?.path, FileManager.default.fileExists(atPath: path) {
            return "sudo ln -sf '\(path)' /usr/local/bin/remotediff"
        }
        return "sudo ln -sf /path/to/RemoteDiff.app/Contents/Resources/remotediff /usr/local/bin/remotediff"
    }

    // MARK: - Usage Examples

    private var usageExamples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                usageRow("remotediff host:path", description: "Open a remote repository")
                Divider().padding(.leading, 12)
                usageRow("remotediff user@host:path", description: "Connect as a specific SSH user")
                Divider().padding(.leading, 12)
                usageRow("remotediff host:path --ref main", description: "Specify git ref")
                Divider().padding(.leading, 12)
                usageRow("remotediff host:path --staged", description: "Include staged changes")
                Divider().padding(.leading, 12)
                usageRow("remotediff host:path --untracked", description: "Include untracked files")
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func usageRow(_ command: String, description: String) -> some View {
        HStack {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Status Check

    private func checkCLIStatus() {
        cliStatus = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            // Check /usr/local/bin/remotediff first (standard install location)
            let standardPath = "/usr/local/bin/remotediff"
            let fm = FileManager.default

            if fm.fileExists(atPath: standardPath) {
                // Resolve symlink target
                let target = (try? fm.destinationOfSymbolicLink(atPath: standardPath)) ?? "direct"
                DispatchQueue.main.async {
                    cliStatus = .installed(path: standardPath, target: target)
                }
                return
            }

            // Fallback: check PATH via `which`
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["remotediff"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? standardPath
                    let target = (try? fm.destinationOfSymbolicLink(atPath: path)) ?? "direct"
                    DispatchQueue.main.async {
                        cliStatus = .installed(path: path, target: target)
                    }
                } else {
                    DispatchQueue.main.async {
                        cliStatus = .notInstalled
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    cliStatus = .notInstalled
                }
            }
        }
    }
}

// MARK: - Keyboard Shortcuts View

struct KeyboardShortcutsView: View {
    private struct ShortcutEntry: Identifiable {
        let id = UUID()
        let keys: String
        let description: String
    }

    private struct ShortcutGroup: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let shortcuts: [ShortcutEntry]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Navigation", icon: "arrow.up.arrow.down", shortcuts: [
            ShortcutEntry(keys: "⌘ ↑", description: "Jump to previous change"),
            ShortcutEntry(keys: "⌘ ↓", description: "Jump to next change"),
            ShortcutEntry(keys: "⌘ [", description: "Previous file"),
            ShortcutEntry(keys: "⌘ ]", description: "Next file"),
        ]),
        ShortcutGroup(title: "Actions", icon: "bolt.fill", shortcuts: [
            ShortcutEntry(keys: "⌘ R", description: "Fetch diff"),
            ShortcutEntry(keys: "⌘ ,", description: "Open Settings"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        shortcutGroup(group)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func shortcutGroup(_ group: ShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(group.title, systemImage: group.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(group.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    HStack {
                        Text(shortcut.description)
                            .font(.system(.body))

                        Spacer()

                        Text(shortcut.keys)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if index < group.shortcuts.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }
}
