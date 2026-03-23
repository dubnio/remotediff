import XCTest
@testable import RemoteDiff

final class SyntaxThemeTests: XCTestCase {

    // MARK: - Hex Color Parsing

    func testHexColorParsesValidSixDigit() {
        let c = HexColor("#FF0000")
        XCTAssertEqual(c.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.green, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.blue, 0.0, accuracy: 0.01)
    }

    func testHexColorParsesLowercase() {
        let c = HexColor("#00ff00")
        XCTAssertEqual(c.red, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.green, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.blue, 0.0, accuracy: 0.01)
    }

    func testHexColorParsesWithoutHash() {
        let c = HexColor("0000FF")
        XCTAssertEqual(c.red, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.green, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.blue, 1.0, accuracy: 0.01)
    }

    func testHexColorParsesEightDigitWithAlpha() {
        let c = HexColor("#FF000080")
        XCTAssertEqual(c.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.alpha, 128.0 / 255.0, accuracy: 0.01)
    }

    func testHexColorInvalidFallsBackToBlack() {
        let c = HexColor("not-a-color")
        XCTAssertEqual(c.red, 0.0)
        XCTAssertEqual(c.green, 0.0)
        XCTAssertEqual(c.blue, 0.0)
    }

    // MARK: - Built-in Themes Exist

    func testAllBuiltInThemesExist() {
        let themes = SyntaxTheme.allThemes
        XCTAssertTrue(themes.count >= 6, "Expected at least 6 built-in themes, got \(themes.count)")
    }

    func testBuiltInThemeIDs() {
        let ids = Set(SyntaxTheme.allThemes.map(\.id))
        XCTAssertTrue(ids.contains("xcode-default"))
        XCTAssertTrue(ids.contains("monokai"))
        XCTAssertTrue(ids.contains("atom-one-dark"))
        XCTAssertTrue(ids.contains("dracula"))
        XCTAssertTrue(ids.contains("solarized-dark"))
        XCTAssertTrue(ids.contains("github-light"))
    }

    func testBuiltInThemesHaveUniqueIDs() {
        let themes = SyntaxTheme.allThemes
        let ids = themes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate theme IDs found")
    }

    func testBuiltInThemesHaveNonEmptyNames() {
        for theme in SyntaxTheme.allThemes {
            XCTAssertFalse(theme.name.isEmpty, "Theme \(theme.id) has empty name")
        }
    }

    // MARK: - Theme Lookup

    func testLookupByID() {
        let theme = SyntaxTheme.theme(for: "monokai")
        XCTAssertEqual(theme.id, "monokai")
        XCTAssertEqual(theme.name, "Monokai")
    }

    func testLookupUnknownIDReturnsDefault() {
        let theme = SyntaxTheme.theme(for: "nonexistent-theme-xyz")
        XCTAssertEqual(theme.id, SyntaxTheme.defaultThemeID)
    }

    func testDefaultThemeID() {
        XCTAssertEqual(SyntaxTheme.defaultThemeID, "atom-one-dark")
    }

    // MARK: - Token Color Mapping

    func testColorForTokenKind() {
        let theme = SyntaxTheme.theme(for: "monokai")
        XCTAssertNotEqual(theme.color(for: .keyword).hex, theme.color(for: .string).hex,
                         "Keywords and strings should have different colors in Monokai")
    }

    func testAllTokenKindsHaveColors() {
        for theme in SyntaxTheme.allThemes {
            let kinds: [SyntaxTokenKind] = [.plain, .keyword, .type, .literal, .string, .comment, .number]
            for kind in kinds {
                let color = theme.color(for: kind)
                XCTAssertFalse(color.hex.isEmpty,
                             "Theme \(theme.id) missing color for \(kind)")
            }
        }
    }

    // MARK: - Editor Chrome Colors

    func testThemeHasEditorColors() {
        for theme in SyntaxTheme.allThemes {
            XCTAssertFalse(theme.editorBackground.hex.isEmpty, "\(theme.id) missing editorBackground")
            XCTAssertFalse(theme.gutterText.hex.isEmpty, "\(theme.id) missing gutterText")
            XCTAssertFalse(theme.additionBackground.hex.isEmpty, "\(theme.id) missing additionBackground")
            XCTAssertFalse(theme.deletionBackground.hex.isEmpty, "\(theme.id) missing deletionBackground")
        }
    }

    // MARK: - Dark/Light Classification

    func testMonokaiIsDark() {
        let theme = SyntaxTheme.theme(for: "monokai")
        XCTAssertTrue(theme.isDark)
    }

    func testGitHubLightIsLight() {
        let theme = SyntaxTheme.theme(for: "github-light")
        XCTAssertFalse(theme.isDark)
    }

    func testXcodeDefaultIsLight() {
        let theme = SyntaxTheme.theme(for: "xcode-default")
        XCTAssertFalse(theme.isDark)
    }

    func testDraculaIsDark() {
        let theme = SyntaxTheme.theme(for: "dracula")
        XCTAssertTrue(theme.isDark)
    }

    // MARK: - Specific Theme Colors (Smoke Tests)

    func testMonokaiKeywordIsPink() {
        let theme = SyntaxTheme.theme(for: "monokai")
        let kw = theme.color(for: .keyword)
        // Monokai keywords are pink/red (#F92672)
        XCTAssertGreaterThan(kw.red, 0.8)
    }

    func testDraculaStringIsPink() {
        let theme = SyntaxTheme.theme(for: "dracula")
        let str = theme.color(for: .string)
        // Dracula strings are yellow-ish (#F1FA8C)
        XCTAssertGreaterThan(str.green, 0.8)
    }

    func testAtomOneDarkCommentIsGray() {
        let theme = SyntaxTheme.theme(for: "atom-one-dark")
        let comment = theme.color(for: .comment)
        // Atom One Dark comments are gray (#5C6370)
        XCTAssertGreaterThan(comment.red, 0.3)
        XCTAssertLessThan(comment.red, 0.5)
    }
}
