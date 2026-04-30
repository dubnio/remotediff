# CLAUDE.md

Project guidelines for AI assistants working on RemoteDiff.

## Build & Test

```bash
swift build          # Build the project
swift test           # Run all tests (121 tests across 7 suites)
./scripts/build-app.sh  # Build .app bundle + DMG installer (or .zip fallback)
```

SPM is the primary build system. There is also a `RemoteDiff.xcodeproj` — when adding/removing/renaming Swift files, update the pbxproj too.

**Distribution**: `build-app.sh` produces a DMG at `.build/release/RemoteDiff-<version>.dmg` with the classic drag-to-Applications installer (app icon + arrow + Applications symlink). Requires `create-dmg` (`brew install create-dmg`); falls back to `.zip` if not installed. Background image is at `scripts/dmg-resources/dmg-background.png` (regenerate with `python3 scripts/create-dmg-background.py`).

**Code signing & notarisation**: `build-app.sh` auto-detects a `Developer ID Application` certificate in the keychain. If found, it signs with the Hardened Runtime + `scripts/entitlements.plist` and (when a `notarytool` keychain profile exists) submits the DMG to Apple, waits for acceptance, and staples the ticket. If no Developer ID cert is found, it falls back to ad-hoc signing.

One-time setup on a new machine: `scripts/setup-signing.sh` walks through:
1. Verifying a `Developer ID Application` cert is in the keychain (Xcode → Settings → Accounts → Manage Certificates… → + → Developer ID Application).
2. Creating a notarisation keychain profile via `xcrun notarytool store-credentials` (needs Apple ID, Team ID, and an [app-specific password](https://appleid.apple.com/account/manage)).

Relevant env vars (override the defaults if needed):
- `RD_SIGN_IDENTITY` — explicit codesign identity (full SHA-1 or `Developer ID Application: …` name).
- `RD_NOTARY_PROFILE` — keychain profile name for `notarytool` (default `RemoteDiffNotary`).

The entitlements file at `scripts/entitlements.plist` keeps the app **unsandboxed** (required for SSH/`~/.ssh` access) and disables library validation (so SSH can load its askpass helper).

## Architecture

- **SwiftUI macOS app**, min deployment target macOS 13
- **No external dependencies** — Foundation, SwiftUI, Combine only
- SSH via `/usr/bin/ssh` with scripts piped through stdin (shell-agnostic: works with fish, zsh, bash)
- App Sandbox disabled (required for SSH process access)
- **NSTextView for code rendering** — `CodePaneView` uses `NSViewRepresentable` wrapping `NSTextView` for multi-line text selection + syntax highlighting. Invisible `LazyVStack` anchor overlay preserves `ScrollViewReader.scrollTo()` support.
- **CLI launcher** — `remotediff` shell script opens the app via `remotediff://` URL scheme. App registers the scheme in `Info.plist` and handles it via `.onOpenURL` in `RemoteDiffApp`.

## Code Layout

| Directory | Purpose |
|-----------|---------|
| `RemoteDiff/Models/` | Data types, parsers, builders, persistence, deep link parsing (no UI imports) |
| `RemoteDiff/Services/` | SSH execution, diff caching, file content fetching, watcher |
| `RemoteDiff/Views/` | All SwiftUI views + language configs |
| `RemoteDiffTests/` | Unit tests |
| `scripts/` | Build script (`build-app.sh`), CLI launcher (`remotediff`), DMG resources |

## Data Model

- `SavedConnection` — SSH host, contains multiple repositories
- `SavedRepository` — repo path + git ref + include flags, nested under connection
- `ConnectionStore` — persists as JSON in UserDefaults (`savedConnections_v2` key)
- `CachedDiffResult` — in-memory diff cache per repository (in `SSHService`)
- `FileContentService` — fetches full file content for Side-by-Side / Full File modes
- `RepoSelection` — current connection + repository IDs
- `DisplayLine` — unified line model for all view modes
- `DisplayLineBuilder` — pure functions that build `[DisplayLine]` from diffs or file content
- `SyntaxHighlighter` — pure tokenizer that splits a line into `[SyntaxToken]` with kinds (keyword, string, comment, number, etc.)
- `SyntaxTheme` — pure data model defining colors (as `HexColor`) for token kinds + editor chrome; 6 built-in themes
- `ThemeStore` — persists selected theme ID in UserDefaults (`selectedThemeID` key), `@ObservableObject`
- `DeepLink` — parses `remotediff://` URLs into host, path, ref, and flags

## Key Patterns

- **One rendering component**: `CodePaneView` renders any `[DisplayLine]` array via `NSTextView` (for multi-line text selection). Builds an `NSAttributedString` with syntax-highlighted tokens, line numbers, per-line diff backgrounds. Caller provides the `ScrollView`. Invisible `LazyVStack` overlay provides scroll anchor `.id()`s.
- **Theming**: `ThemeStore` owned by `RemoteDiffApp`, threaded through `ContentView` → `DiffView` → `CodePaneView`. Settings accessible via ⌘, (macOS Settings scene). To add a theme: add a `static let` in `SyntaxTheme` and register in `allThemes`.
- **Synced scrolling**: Dual-pane views (Diff, Side by Side) share a single `ScrollView` so both panes scroll together. `dualPaneScroll()` in `DiffView` encapsulates this pattern.
- **Change navigation**: `ScrollViewReader` + `scrollTo()` drives ⌘↑/⌘↓ jump-to-change. Anchors are hunk IDs in diff mode, grouped changed line IDs in file modes. `changeAnchors(for:)` computes targets per view mode.
- **Deep linking**: `RemoteDiffApp` owns `pendingDeepLink` state, passes as `@Binding` to `ContentView`. On `.onOpenURL`, the URL is parsed via `DeepLink.parse(from:)`. `ContentView.handleDeepLink()` finds or creates a matching connection+repo, selects it, and auto-fetches.
- **`DisplayLineBuilder`** is pure logic with no UI dependencies — fully unit tested.
- Script building centralized in `SSHService.buildDiffScript()` / `buildPollScript()`.
- SSH execution uses `runSSHBash()` which pipes scripts via stdin to avoid quoting issues.
- `ControlMasterWatcher` reuses `SSHService.runSSHBash()` with extra ControlPath args.
- `FileContentService` fetches old + new file content in a single SSH call using a separator.
- Fetch triggers live in `ContentView` (owns the state), not in `DiffView` (avoids stale closures).
- `SavedRepository.init(from:)` uses `decodeIfPresent` for backward compatibility.
- `LanguageConfig.detect(from:)` maps file extensions to language definitions (30+ languages).

## CLI Tool

The `scripts/remotediff` bash script provides terminal access to the app:

```bash
remotediff mac-studio:Development/myapp/api                    # basic
remotediff ernesto@mac-studio:Development/myapp/api            # with SSH user
remotediff mac-studio:Development/myapp/api --ref main         # custom ref
remotediff mac-studio:~/projects/api --staged --untracked           # with flags
remotediff --install                                                # symlink to /usr/local/bin
```

The script converts `[user@]host:path` into a `remotediff://open?host=...&path=...` URL and calls `open`. The `user@host` string is passed as-is to SSH, which handles it natively. The app handles the URL via `.onOpenURL` → `DeepLink.parse()` → `ContentView.handleDeepLink()`. If no matching connection/repo exists, one is created automatically.

**Password authentication**: `SSHService.runSSHBash()` sets `SSH_ASKPASS` to a bundled `remotediff-askpass` helper script, which shows a native macOS dialog via `osascript` when SSH needs a password or key passphrase. `DISPLAY` and `SSH_ASKPASS_REQUIRE=prefer` are also set so SSH uses the askpass helper when there's no TTY.

## View Modes

All dual-pane modes use `dualPaneScroll()` (shared `ScrollView` via `GeometryReader` + `ScrollViewReader`). Single-pane uses `scrollableContent()`.

| Mode | Data Source | Rendering |
|------|------------|-----------|
| **Diff** | `SSHService.fileDiffs` → `DisplayLineBuilder.buildDiffLines()` | `dualPaneScroll` (left/right) |
| **Side by Side** | `FileContentService` old/new content → `DisplayLineBuilder.buildFullFileLines()` | `dualPaneScroll` with Old/New labels |
| **Full File** | `FileContentService` new content → `DisplayLineBuilder.buildFullFileLines()` | `scrollableContent` (single pane) |

## Testing

Tests in `RemoteDiffTests/`:
- `DiffParserTests` — 19 tests for unified diff parsing including untracked files
- `DisplayLineBuilderTests` — 30 tests for display line building, inline ranges, deletion markers, hunk formatting
- `SSHConfigTests` — 5 tests for SSH config parsing
- `SyntaxHighlighterTests` — 32 tests for syntax tokenization (keywords, strings, comments, numbers, block comments, edge cases)
- `SyntaxThemeTests` — 22 tests for theme registry, hex color parsing, built-in theme validation, dark/light classification
- `DeepLinkTests` — 13 tests for URL scheme parsing, user@host format, edge cases, invalid inputs

Run `swift test` after modifying `DiffParser`, `DisplayLineBuilder`, `SyntaxHighlighter`, `SyntaxTheme`, `SSHConfig`, or `DeepLink`.

## SSH Authentication

`SSHService.runSSHBash()` sets environment variables on every `Process` to enable GUI password prompts:
- `SSH_ASKPASS` → path to bundled `remotediff-askpass` (osascript-based native dialog)
- `SSH_ASKPASS_REQUIRE=prefer` → tells SSH to prefer askpass even without a TTY
- `DISPLAY=:0` → required for SSH to trigger askpass

The askpass helper is resolved once via `SSHService.askpassPath` (lazy static). It checks: (1) `Bundle.main.resources/remotediff-askpass` for `.app` installs, (2) `scripts/remotediff-askpass` relative to executable for dev builds.
