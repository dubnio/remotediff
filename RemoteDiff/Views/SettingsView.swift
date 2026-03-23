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
