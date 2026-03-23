# CLAUDE.md

Project guidelines for AI assistants working on RemoteDiff.

## Build & Test

```bash
swift build          # Build the project
swift test           # Run all tests (37 tests across 4 suites)
./scripts/build-app.sh  # Build distributable .app bundle + .zip
```

SPM is the primary build system. There is also a `RemoteDiff.xcodeproj` — when adding/removing/renaming Swift files, update the pbxproj too.

## Architecture

- **SwiftUI macOS app**, min deployment target macOS 13
- **No external dependencies** — Foundation, SwiftUI, Combine only
- SSH via `/usr/bin/ssh` with scripts piped through stdin (shell-agnostic: works with fish, zsh, bash)
- App Sandbox disabled (required for SSH process access)
- **Pure SwiftUI rendering** — no NSTextView/NSViewRepresentable. All code views use `LazyVStack` + `Text`.

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

## Key Patterns

- **One rendering component**: `CodePaneView` renders any `[DisplayLine]` array. Used by all three view modes (Diff, Full File, Side by Side).
- **`DisplayLineBuilder`** is pure logic with no UI dependencies — fully unit tested.
- Script building centralized in `SSHService.buildDiffScript()` / `buildPollScript()`.
- SSH execution uses `runSSHBash()` which pipes scripts via stdin to avoid quoting issues.
- `ControlMasterWatcher` reuses `SSHService.runSSHBash()` with extra ControlPath args.
- `FileContentService` fetches old + new file content in a single SSH call using a separator.
- Fetch triggers live in `ContentView` (owns the state), not in `DiffView` (avoids stale closures).
- `SavedRepository.init(from:)` uses `decodeIfPresent` for backward compatibility.
- `LanguageConfig.detect(from:)` maps file extensions to language definitions (30+ languages).

## View Modes

| Mode | Data Source | Rendering |
|------|------------|-----------|
| **Diff** | `SSHService.fileDiffs` → `DisplayLineBuilder.buildDiffLines()` | Two `CodePaneView`s (left/right) |
| **Side by Side** | `FileContentService` old/new content → `DisplayLineBuilder.buildFullFileLines()` | Two `CodePaneView`s with Old/New labels |
| **Full File** | `FileContentService` new content → `DisplayLineBuilder.buildFullFileLines()` | One `CodePaneView` |

## Testing

Tests in `RemoteDiffTests/`:
- `DiffParserTests` — 19 tests for unified diff parsing including untracked files
- `DisplayLineBuilderTests` — 13 tests for display line building across all modes
- `SSHConfigTests` — 5 tests for SSH config parsing

Run `swift test` after modifying `DiffParser`, `DisplayLineBuilder`, or `SSHConfig`.
