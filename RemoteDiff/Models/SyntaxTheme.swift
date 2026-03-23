import Foundation

// MARK: - Hex Color

/// A color represented as a hex string, parseable without AppKit/SwiftUI.
/// Supports "#RRGGBB", "RRGGBB", "#RRGGBBAA", "RRGGBBAA".
struct HexColor: Equatable {
    let hex: String
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ hex: String) {
        self.hex = hex
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex

        guard let value = UInt64(cleaned, radix: 16) else {
            self.red = 0; self.green = 0; self.blue = 0; self.alpha = 1
            return
        }

        if cleaned.count == 8 {
            self.red   = Double((value >> 24) & 0xFF) / 255.0
            self.green = Double((value >> 16) & 0xFF) / 255.0
            self.blue  = Double((value >> 8)  & 0xFF) / 255.0
            self.alpha = Double( value        & 0xFF) / 255.0
        } else {
            self.red   = Double((value >> 16) & 0xFF) / 255.0
            self.green = Double((value >> 8)  & 0xFF) / 255.0
            self.blue  = Double( value        & 0xFF) / 255.0
            self.alpha = 1.0
        }
    }
}

// MARK: - Syntax Theme

/// A complete color theme for syntax highlighting and editor chrome.
/// Pure data — no UI framework imports. Easy to add new themes: just add a static property
/// and register it in `allThemes`.
struct SyntaxTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool

    // Token colors
    let plain: HexColor
    let keyword: HexColor
    let type: HexColor
    let literal: HexColor
    let string: HexColor
    let comment: HexColor
    let number: HexColor

    // Editor chrome
    let editorBackground: HexColor
    let gutterText: HexColor
    let additionBackground: HexColor
    let deletionBackground: HexColor
    let hunkHeaderBackground: HexColor
    let hunkHeaderText: HexColor

    /// Returns the token color for a given syntax token kind.
    func color(for kind: SyntaxTokenKind) -> HexColor {
        switch kind {
        case .plain:   return plain
        case .keyword: return keyword
        case .type:    return type
        case .literal: return literal
        case .string:  return string
        case .comment: return comment
        case .number:  return number
        }
    }
}

// MARK: - Theme Registry

extension SyntaxTheme {

    static let defaultThemeID = "atom-one-dark"

    /// All built-in themes. To add a new theme, create a static property below
    /// and add it to this array.
    static let allThemes: [SyntaxTheme] = [
        .xcodeDefault,
        .monokai,
        .atomOneDark,
        .dracula,
        .solarizedDark,
        .githubLight,
    ]

    /// Look up a theme by ID, falling back to the default theme.
    static func theme(for id: String) -> SyntaxTheme {
        allThemes.first { $0.id == id } ?? allThemes.first { $0.id == defaultThemeID }!
    }
}

// MARK: - Built-in Themes

extension SyntaxTheme {

    // MARK: Xcode Default (Light)

    static let xcodeDefault = SyntaxTheme(
        id: "xcode-default",
        name: "Xcode Default",
        isDark: false,
        plain:    HexColor("#000000"),
        keyword:  HexColor("#AD3DA4"),
        type:     HexColor("#703DAA"),
        literal:  HexColor("#272AD8"),
        string:   HexColor("#D12F1B"),
        comment:  HexColor("#707F8C"),
        number:   HexColor("#272AD8"),
        editorBackground:    HexColor("#FFFFFF"),
        gutterText:          HexColor("#A0A0A0"),
        additionBackground:  HexColor("#E6FFEC"),
        deletionBackground:  HexColor("#FFEBE9"),
        hunkHeaderBackground: HexColor("#F0F4FF"),
        hunkHeaderText:      HexColor("#6E7781")
    )

    // MARK: Monokai

    static let monokai = SyntaxTheme(
        id: "monokai",
        name: "Monokai",
        isDark: true,
        plain:    HexColor("#F8F8F2"),
        keyword:  HexColor("#F92672"),
        type:     HexColor("#66D9EF"),
        literal:  HexColor("#AE81FF"),
        string:   HexColor("#E6DB74"),
        comment:  HexColor("#75715E"),
        number:   HexColor("#AE81FF"),
        editorBackground:    HexColor("#272822"),
        gutterText:          HexColor("#90908A"),
        additionBackground:  HexColor("#2EA04326"),
        deletionBackground:  HexColor("#F8514926"),
        hunkHeaderBackground: HexColor("#3E3D32"),
        hunkHeaderText:      HexColor("#90908A")
    )

    // MARK: Atom One Dark

    static let atomOneDark = SyntaxTheme(
        id: "atom-one-dark",
        name: "Atom One Dark",
        isDark: true,
        plain:    HexColor("#ABB2BF"),
        keyword:  HexColor("#C678DD"),
        type:     HexColor("#E5C07B"),
        literal:  HexColor("#D19A66"),
        string:   HexColor("#98C379"),
        comment:  HexColor("#5C6370"),
        number:   HexColor("#D19A66"),
        editorBackground:    HexColor("#282C34"),
        gutterText:          HexColor("#636D83"),
        additionBackground:  HexColor("#2EA04326"),
        deletionBackground:  HexColor("#F8514926"),
        hunkHeaderBackground: HexColor("#2C313C"),
        hunkHeaderText:      HexColor("#636D83")
    )

    // MARK: Dracula

    static let dracula = SyntaxTheme(
        id: "dracula",
        name: "Dracula",
        isDark: true,
        plain:    HexColor("#F8F8F2"),
        keyword:  HexColor("#FF79C6"),
        type:     HexColor("#8BE9FD"),
        literal:  HexColor("#BD93F9"),
        string:   HexColor("#F1FA8C"),
        comment:  HexColor("#6272A4"),
        number:   HexColor("#BD93F9"),
        editorBackground:    HexColor("#282A36"),
        gutterText:          HexColor("#6272A4"),
        additionBackground:  HexColor("#50FA7B26"),
        deletionBackground:  HexColor("#FF555526"),
        hunkHeaderBackground: HexColor("#343746"),
        hunkHeaderText:      HexColor("#6272A4")
    )

    // MARK: Solarized Dark

    static let solarizedDark = SyntaxTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        isDark: true,
        plain:    HexColor("#839496"),
        keyword:  HexColor("#859900"),
        type:     HexColor("#268BD2"),
        literal:  HexColor("#2AA198"),
        string:   HexColor("#2AA198"),
        comment:  HexColor("#586E75"),
        number:   HexColor("#D33682"),
        editorBackground:    HexColor("#002B36"),
        gutterText:          HexColor("#586E75"),
        additionBackground:  HexColor("#859900"),
        deletionBackground:  HexColor("#DC322F26"),
        hunkHeaderBackground: HexColor("#073642"),
        hunkHeaderText:      HexColor("#586E75")
    )

    // MARK: GitHub Light

    static let githubLight = SyntaxTheme(
        id: "github-light",
        name: "GitHub Light",
        isDark: false,
        plain:    HexColor("#24292F"),
        keyword:  HexColor("#CF222E"),
        type:     HexColor("#8250DF"),
        literal:  HexColor("#0550AE"),
        string:   HexColor("#0A3069"),
        comment:  HexColor("#6E7781"),
        number:   HexColor("#0550AE"),
        editorBackground:    HexColor("#FFFFFF"),
        gutterText:          HexColor("#8C959F"),
        additionBackground:  HexColor("#DAFBE1"),
        deletionBackground:  HexColor("#FFEBE9"),
        hunkHeaderBackground: HexColor("#DDF4FF"),
        hunkHeaderText:      HexColor("#6E7781")
    )
}
