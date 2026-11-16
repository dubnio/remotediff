# CLAUDE.md

Project guidelines for AI assistants working on RemoteDiff.

## Build & Test

```bash
swift build          # Build the project
swift test           # Run all tests
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

The entitlements file at `scripts/entitlements.plist` keeps the app **unsandboxed** (required for SSH/`~/.ssh` access). Library validation stays on (no `disable-library-validation`): ssh and the askpass helper are separate child processes, not libraries loaded into the app.

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
- `SSHConnectionManager` — owns the one app-owned ssh ControlMaster per host (`Services/`); see SSH
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
- **Error display**: `SSHService.failureMessage` puts a one-line summary (`ErrorSummary`) on line 1, then hints, then stderr. `ErrorMessageView` shows that line with Copy and, if there is more, "Details…" (`ErrorDetailsSheet`, text captured when opened). `LiveStatusBar` does the same in one line. Never a bare red `Text` with `lineLimit`.
- **`DisplayLineBuilder`** is pure logic with no UI dependencies — fully unit tested.
- Script building centralized in `SSHService.buildDiffScript()` / `buildPollScript()` / `buildBranchScript()` / `buildFileContentScript()`.
- SSH rules (quoting, option order, the app-owned ControlMaster, prompts): see **SSH** below.
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

## View Modes

All dual-pane modes use `dualPaneScroll()` (shared `ScrollView` via `GeometryReader` + `ScrollViewReader`). Single-pane uses `scrollableContent()`.

| Mode | Data Source | Rendering |
|------|------------|-----------|
| **Diff** | `SSHService.fileDiffs` → `DisplayLineBuilder.buildDiffLines()` | `dualPaneScroll` (left/right) |
| **Side by Side** | `FileContentService` old/new content → `DisplayLineBuilder.buildFullFileLines()` (with `modifiedLines`) + `ConnectorLink.compute()` | `dualPaneScroll` with Old/New labels and `ConnectorRibbonsView` in the gap |
| **Full File** | `FileContentService` new content → `DisplayLineBuilder.buildFullFileLines()` (with `modifiedLines`) | `scrollableContent` (single pane) |

**Side-by-Side connector ribbons.** Each pane renders its own raw, unpadded full-file content (different line counts on each side). `ConnectorLink.compute(fileDiff:)` walks the unified diff and produces, for each contiguous deletion/addition cluster, a link with **separate old-line and new-line ranges**. `ConnectorRibbonsView` (canvas-based) draws cubic Bézier ribbons connecting those Y ranges in the 28 px gap between panes — wedge-shaped for pure adds/dels, trapezoidal for modifications. Width is an explicit parameter; height equals the taller pane.

**Modification highlighting.** `DiffLineType` includes a display-only `.modification` case used by `buildFullFileLines` when a line number is in the `modifiedLines` set (computed via `DisplayLineBuilder.modifiedLineNumbers(fileDiff:side:)`). Themes carry a `modificationBackground` + `inlineModificationBackground` (typically blue) so modification rows render visually distinct from pure adds (green) / dels (red). Indicator glyph is `~`.

## Testing

Test suites in `RemoteDiffTests/`:
- `DiffParserTests` — unified diff parsing including untracked files
- `DisplayLineBuilderTests` — display line building, inline ranges, deletion markers, hunk formatting, aligned side-by-side, `ChangeRegion.compute`, `ConnectorLink.compute` (incl. interleaved del/add collapse), `modifiedLineNumbers`, and `buildFullFileLines` modified-lines precedence
- `SSHConfigTests` — SSH config parsing, ssh argv building and option order, `SSHConnectionManager` argv / socket paths / fail-fast, failure messages and hints
- `SyntaxHighlighterTests` — syntax tokenization (keywords, strings, comments, numbers, block comments, **Python triple-quoted strings with multi-line state**, edge cases)
- `SyntaxThemeTests` — theme registry, hex color parsing, built-in theme validation, dark/light classification
- `DeepLinkTests` — URL scheme parsing, user@host format, edge cases, invalid inputs, host/ref/path injection validation
- `SSHServiceTests` — `stashBeforeSwitching`, `shellQuote`, `shellQuotePath`, and `buildDiffScript` / `buildPollScript` / `buildBranchScript` / `buildFileContentScript` output
- `FileGroupTests` — sidebar directory grouping (preserves first-appearance order, root files, breadcrumb rendering)
- `ErrorSummaryTests` — error summaries (ssh rules only on exit 255, git rules otherwise, spoofing by banners and remote stderr) and the summary / details split

Run `swift test` after modifying any of: `DiffParser`, `DisplayLineBuilder`, `SyntaxHighlighter`, `SyntaxTheme`, `SSHConfig`, `DeepLink`, the `SSHService` script builders / shell quoting / `failureMessage`, `ErrorSummary`, or the `FileGroup` model in `SidebarView.swift`.

## SSH

All ssh code is in `SSHService` and `SSHConnectionManager` (`Services/`); their doc comments explain each ssh option. Keep these invariants:

- **git never runs on the Mac.** Every remote operation is a script piped to `/usr/bin/ssh <host> bash` by `SSHService.runSSHBash()` (shell-agnostic). Anything interpolated into a script goes through `SSHService.shellQuote` / `shellQuotePath`; script builders are static on `SSHService` so they're testable; deep-link values are validated in `DeepLink.parse`.
- **One ssh at a time.** `runSSHBash` runs ssh on a serial queue so Touch ID / askpass prompts never overlap; stale requests are dropped via `shouldRun`.
- **Our options first.** ssh keeps the first value of an option, so every argv starts with `hostKeyOptionArgs` (`StrictHostKeyChecking=yes`), `authOptionArgs` (password / keyboard-interactive off unless the host is in `passwordAuthHosts`), `connectionOptionArgs` and `forwardingOptionArgs` (no agent / X11 / port forwarding: git runs on an untrusted remote). Build argv with `SSHService.sshArguments` / `SSHConnectionManager.masterArguments`, never by hand.
- **One app-owned ControlMaster per host string.** `SSHConnectionManager` starts it on first use (inside the serial queue) with its own socket under `$TMPDIR/rdcm/<pid>/`; clients use `clientArguments` (socket only, every auth method off), so a missing master fails instead of prompting. Never reuse, check or close the user's own ControlMaster. `~/.ssh/config` otherwise applies.
- **Clean up after ourselves.** Masters close at quit, when "Allow password authentication" changes for the host, and when the last connection using the host is deleted or edited; `removeLeftovers()` cleans up after a crashed instance at launch.
- **Only the user causes prompts.** Watch-mode polls (`mayOpenConnection: false`) never authenticate; with no master they ask the user to click Reconnect. `ControlMasterWatcher` only polls through `runSSHBash` and owns no connection.
- **Password auth is per-host opt-in** (`setPasswordAuth(allowed:forHost:)`, UserDefaults `passwordAuthHosts`); the grant is removed with the last connection for that host.
- **Errors explain the next step.** `SSHService.failureMessage` adds `authFailureHint` / `hostKeyFailureHint` to ssh errors. Host-key advice is `ssh -o StrictHostKeyChecking=ask <host>` in Terminal (not `ssh-keyscan`, which ignores ~/.ssh/config and verifies nothing).
- **Known limitation (task #14):** ProxyJump/ProxyCommand hops run their own ssh with the user's config and without our options.

`SSHService.sshEnvironment()` sets `SSH_ASKPASS` (`scripts/remotediff-askpass`, bundled in the .app, located by `SSHService.askpassPath`), `SSH_ASKPASS_REQUIRE=prefer` and `DISPLAY=:0`, so ssh shows native dialogs for passwords and key passphrases. The helper must pass the prompt to `osascript` as an argument (never in the script source, so a server can't inject AppleScript), refuse host-key questions, exit 1 on Cancel or any failure, and close its dialog when the ssh that asked exits.
