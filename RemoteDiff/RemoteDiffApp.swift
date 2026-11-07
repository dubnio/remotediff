import SwiftUI
import AppKit

@main
struct RemoteDiffApp: App {
    @StateObject private var themeStore = ThemeStore()
    @State private var pendingDeepLink: DeepLink?

    init() {
        // Set app icon from asset catalog
        if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(themeStore: themeStore, pendingDeepLink: $pendingDeepLink)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { url in
                    if let link = DeepLink.parse(from: url) {
                        pendingDeepLink = link
                    } else {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Ignored invalid remotediff:// link"
                        alert.informativeText = "This remotediff:// link is malformed or contains characters RemoteDiff does not accept."
                        alert.addButton(withTitle: "OK")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        alert.runModal()
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView(themeStore: themeStore)
        }
    }
}
