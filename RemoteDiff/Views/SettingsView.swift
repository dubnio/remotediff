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
