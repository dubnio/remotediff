import SwiftUI

// MARK: - Theme Store

/// Persists the selected syntax theme and provides it to the view hierarchy.
class ThemeStore: ObservableObject {
    @Published var currentTheme: SyntaxTheme

    private static let storageKey = "selectedThemeID"

    init() {
        let savedID = UserDefaults.standard.string(forKey: Self.storageKey) ?? SyntaxTheme.defaultThemeID
        self.currentTheme = SyntaxTheme.theme(for: savedID)
    }

    func select(_ theme: SyntaxTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.id, forKey: Self.storageKey)
    }
}

// MARK: - HexColor → SwiftUI Color

extension HexColor {
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
