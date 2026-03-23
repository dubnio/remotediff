import SwiftUI
import AppKit

@main
struct RemoteDiffApp: App {
    @StateObject private var themeStore = ThemeStore()

    init() {
        // Set app icon from asset catalog
        if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(themeStore: themeStore)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView(themeStore: themeStore)
        }
    }
}
