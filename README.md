# RemoteDiff

A native macOS app for viewing git diffs from remote servers over SSH, with side-by-side file comparison, Bézier change connectors, syntax highlighting, and live change watching. Includes a CLI tool for opening repos directly from the terminal.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![Tests](https://img.shields.io/badge/tests-165%20passing-brightgreen)

## Features

- **Three view modes** — Side-by-side full file (with Bézier connector ribbons), diff hunks, or single-pane full file. Dual-pane modes scroll in sync.
- **Bézier connector ribbons** — Curved swooping ribbons in the gap between Side-by-Side panes connect changed regions; modifications get a distinct blue tint, additions green, deletions red.
- **Modification-aware highlighting** — Lines that are part of a deletion-paired-with-addition (real edits) render with a blue background, distinct from pure additions (green) and pure deletions (red).
- **Syntax highlighting** — 30+ language configs, multi-line state tracking (block comments, Python triple-quoted docstrings), 6 built-in color themes (Xcode Default, Monokai, Atom One Dark, Dracula, Solarized Dark, GitHub Light).
- **SSH git diff** — Fetches diffs from remote hosts via `/usr/bin/ssh`, shell-agnostic (bash, fish, zsh).
- **Live watching** — ControlMaster-based persistent SSH with 2 s polling and 800 ms debounce.
- **Connection management** — Save SSH connections with multiple repositories, auto-fetch on selection.
- **Files grouped by directory** — Sidebar groups changed files under breadcrumb directory headers.
- **Auto-scroll to first change** — Opening a file or switching modes scrolls to the first change automatically.
- **CLI launcher** — Open repos from the terminal: `remotediff host:path` (like `code` for VS Code).
- **Untracked & staged files** — Option to include untracked and staged files in the diff.
- **Remote branch display** — Shows the current branch on the remote, auto-refreshes.
- **SSH config integration** — Auto-parses `~/.ssh/config` for host picker.
- **Diff result caching** — Switch between repos without re-fetching.
- **Deep linking** — Custom URL scheme `remotediff://` for terminal → app integration.
- **Keyboard shortcuts** — ⌘R refresh, ⌘[ ⌘] navigate files, ⌘↑ ⌘↓ jump between changes, ⌘, settings.

## Building

```bash
swift build                # debug build
swift test                 # 165 tests across 7 suites
open RemoteDiff.xcodeproj  # or use Xcode
```

## Distributing

```bash
./scripts/build-app.sh
```

Produces a notarised, stapled `.dmg` at `.build/release/RemoteDiff-<version>.dmg` with the classic drag-to-Applications installer (background image + Applications symlink). Recipients can double-click and install — no Gatekeeper warnings, no `xattr -cr` workaround. Falls back to `.zip` if `create-dmg` isn't installed (`brew install create-dmg`).

The script auto-detects what's available in the keychain and degrades gracefully:

| Available                                              | Result                                                                |
|--------------------------------------------------------|-----------------------------------------------------------------------|
| Developer ID cert + notarytool keychain profile        | Sign w/ Hardened Runtime → notarise → staple. Ship-ready DMG. ✅       |
| Developer ID cert only                                 | Sign w/ Hardened Runtime; first launch needs right-click → Open. ⚠️    |
| Neither                                                | Ad-hoc signed DMG; recipients may need `xattr -cr` to bypass.         |

### One-time signing setup

For maintainers with a [paid Apple Developer Program](https://developer.apple.com/programs/) membership:

```bash
./scripts/setup-signing.sh
```

This guided helper:
1. Verifies a `Developer ID Application` certificate is in your keychain (create one via Xcode → Settings → Accounts → Manage Certificates… → + → Developer ID Application).
2. Stores notarisation credentials via `xcrun notarytool store-credentials` (needs your Apple ID, Team ID, and an [app-specific password](https://appleid.apple.com/account/manage)).

After that, every `build-app.sh` run automatically signs, notarises, and staples.

Override env vars:
- `RD_SIGN_IDENTITY` — explicit codesign identity (full SHA-1 or `Developer ID Application: …` name)
- `RD_NOTARY_PROFILE` — keychain profile name for `notarytool` (default `RemoteDiffNotary`)

## CLI Tool

Open remote repos directly from the terminal — similar to `code` for VS Code:

```bash
# Install the CLI (creates a symlink in /usr/local/bin)
./scripts/remotediff --install

# Basic usage
remotediff mac-studio:Development/myapp/api

# With SSH user (prompts for password if needed)
remotediff ernesto@mac-studio:Development/myapp/api

# With options
remotediff mac-studio:~/projects/api --ref main
remotediff prod-server:apps/backend --ref HEAD~3 --staged --untracked
```

The CLI converts `[user@]host:path` into a `remotediff://` URL and opens it. The app finds or creates a matching connection + repository, then fetches the diff. If RemoteDiff is already running, it switches to the requested repo; otherwise it launches.

**Password support**: when SSH needs a password or key passphrase, a native macOS dialog appears via the bundled `remotediff-askpass` helper — no terminal interaction required, both from the CLI and from the GUI.

After building with `build-app.sh`, the CLI is also bundled inside the app at `RemoteDiff.app/Contents/Resources/remotediff`.

## Usage

### From the GUI

1. Click **+** to create a connection and enter an SSH host
2. Add repositories with a path and git ref
3. Select a repo — auto-fetches the diff and opens at the first change
4. Use the segmented picker to switch between **Side by Side**, **Diff**, and **Full File** views
5. Use ↑/↓ buttons (or ⌘↑/⌘↓) to jump between changes
6. Toggle **Watch** for live change detection
7. ⌘, opens Settings (theme picker)

### From the Terminal

```bash
remotediff [user@]<host>:<path> [--ref REF] [--staged] [--untracked]
```

## Project Structure

```
RemoteDiff/
├── Models/
│   ├── DiffModels.swift          # DiffLine, DiffHunk, FileDiff, SSHHost, RepoSelection
│   ├── DiffParser.swift          # Unified diff parser
│   ├── DisplayLineBuilder.swift  # Display lines, ConnectorLink, ChangeRegion, modified-line classification
│   ├── SyntaxHighlighter.swift   # Pure tokenizer with multi-line state (block comments + triple strings)
│   ├── SyntaxTheme.swift         # 6 built-in themes + HexColor model
│   ├── ThemeStore.swift          # Selected theme persistence
│   ├── SSHConfig.swift           # ~/.ssh/config parser
│   ├── ConnectionStore.swift     # Connection + Repository persistence
│   └── DeepLink.swift            # URL scheme parser for CLI integration
├── Services/
│   ├── SSHService.swift          # SSH execution, diff fetching, caching, askpass plumbing
│   ├── FileContentService.swift  # Full file content fetching for side-by-side/full file modes
│   └── ControlMasterWatcher.swift # Persistent SSH + change polling
├── Views/
│   ├── CodePaneView.swift        # NSTextView-backed unified code rendering with line backgrounds
│   ├── ConnectorRibbonsView.swift # Cubic Bézier connector ribbons in the gap between panes
│   ├── DiffView.swift            # View mode switching, change navigation, file header
│   ├── SidebarView.swift         # Connection/repo browser, files grouped by directory
│   ├── LiveStatusBar.swift       # Watcher status indicator
│   ├── SettingsView.swift        # Theme picker
│   └── LanguageConfig.swift      # 30+ language definitions
├── ContentView.swift             # Main NavigationSplitView
└── RemoteDiffApp.swift           # App entry point + URL scheme handler

scripts/
├── build-app.sh                  # Builds .app bundle + signs + notarises + staples DMG
├── setup-signing.sh              # One-time signing/notarisation setup helper
├── entitlements.plist            # Hardened Runtime entitlements (no sandbox, allow unsigned dylib loads)
├── remotediff                    # CLI launcher script
├── remotediff-askpass            # SSH_ASKPASS helper (native macOS password dialog)
├── create-dmg-background.py      # Regenerates the DMG installer background image
└── dmg-resources/                # DMG installer assets
```

## Requirements

- macOS 13 Ventura or later
- SSH access to remote hosts (key-based auth recommended; password auth supported via native dialog)
- Git installed on the remote server
- For maintainers building signed releases: Xcode + paid Apple Developer Program membership
