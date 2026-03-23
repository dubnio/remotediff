# CLAUDE.md

Project guidelines for AI assistants working on RemoteDiff.

## Build & Test

```bash
swift build          # Build the project
swift test           # Run all tests (91 tests across 6 suites)
./scripts/build-app.sh  # Build distributable .app bundle + .zip
```

SPM is the primary build system. There is also a `RemoteDiff.xcodeproj` — when adding/removing/renaming Swift files, update the pbxproj too.

## Architecture

- **SwiftUI macOS app**, min deployment target macOS 13
- **No external dependencies** — Foundation, SwiftUI, Combine only
- SSH via `/usr/bin/ssh` with scripts piped through stdin (shell-agnostic: works with fish, zsh, bash)
- App Sandbox disabled (required for SSH process access)
- **NSTextView for code rendering** — `CodePaneView` uses `NSViewRepresentable` wrapping `NSTextView` for multi-line text selection + syntax highlighting. Invisible `LazyVStack` anchor overlay preserves `ScrollViewReader.scrollTo()` support.

## Code Layout

| Directory | Purpose |
|-----------|---------|
| `RemoteDiff/Models/` | Data types, parsers, builders, persistence (no UI imports) |
| `RemoteDiff/Services/` | SSH execution, diff caching, file content fetching, watcher |
| `RemoteDiff/Views/` | All SwiftUI views + language configs |
| `RemoteDiffTests/` | Unit tests |

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

## Key Patterns

- **One rendering component**: `CodePaneView` renders any `[DisplayLine]` array via `NSTextView` (for multi-line text selection). Builds an `NSAttributedString` with syntax-highlighted tokens, line numbers, per-line diff backgrounds. Caller provides the `ScrollView`. Invisible `LazyVStack` overlay provides scroll anchor `.id()`s.
- **Theming**: `ThemeStore` owned by `RemoteDiffApp`, threaded through `ContentView` → `DiffView` → `CodePaneView`. Settings accessible via ⌘, (macOS Settings scene). To add a theme: add a `static let` in `SyntaxTheme` and register in `allThemes`.
- **Synced scrolling**: Dual-pane views (Diff, Side by Side) share a single `ScrollView` so both panes scroll together. `dualPaneScroll()` in `DiffView` encapsulates this pattern.
- **Change navigation**: `ScrollViewReader` + `scrollTo()` drives ⌘↑/⌘↓ jump-to-change. Anchors are hunk IDs in diff mode, grouped changed line IDs in file modes. `changeAnchors(for:)` computes targets per view mode.
- **`DisplayLineBuilder`** is pure logic with no UI dependencies — fully unit tested.
- Script building centralized in `SSHService.buildDiffScript()` / `buildPollScript()`.
- SSH execution uses `runSSHBash()` which pipes scripts via stdin to avoid quoting issues.
- `ControlMasterWatcher` reuses `SSHService.runSSHBash()` with extra ControlPath args.
- `FileContentService` fetches old + new file content in a single SSH call using a separator.
- Fetch triggers live in `ContentView` (owns the state), not in `DiffView` (avoids stale closures).
- `SavedRepository.init(from:)` uses `decodeIfPresent` for backward compatibility.
- `LanguageConfig.detect(from:)` maps file extensions to language definitions (30+ languages).

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
- `DisplayLineBuilderTests` — 13 tests for display line building across all modes
- `SSHConfigTests` — 5 tests for SSH config parsing
- `SyntaxHighlighterTests` — 32 tests for syntax tokenization (keywords, strings, comments, numbers, block comments, edge cases)
- `SyntaxThemeTests` — 22 tests for theme registry, hex color parsing, built-in theme validation, dark/light classification

Run `swift test` after modifying `DiffParser`, `DisplayLineBuilder`, `SyntaxHighlighter`, `SyntaxTheme`, or `SSHConfig`.
