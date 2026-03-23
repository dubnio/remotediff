# RemoteDiff

A native macOS app for viewing git diffs from remote servers over SSH, with side-by-side file comparison and live change watching.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Three view modes** — Side-by-side full file, diff hunks, or single-pane full file (dual-pane modes scroll in sync)
- **SSH git diff** — Fetches diffs from remote hosts via `/usr/bin/ssh`, shell-agnostic (bash, fish, zsh)
- **Live watching** — ControlMaster-based persistent SSH with 2s polling and 800ms debounce
- **Connection management** — Save SSH connections with multiple repositories, auto-fetch on selection
- **Untracked & staged files** — Option to include untracked and staged files in the diff
- **Remote branch display** — Shows the current branch on the remote, auto-refreshes
- **30+ language configs** — File-extension-based language detection for syntax-aware rendering
- **SSH config integration** — Auto-parses `~/.ssh/config` for host picker
- **Diff result caching** — Switch between repos without re-fetching
- **Keyboard shortcuts** — ⌘R refresh, ⌘[ ⌘] navigate files, ⌘↑ ⌘↓ jump between changes

## Building

```bash
swift build
swift test       # 37 tests
open RemoteDiff.xcodeproj
```

## Distributing

```bash
./scripts/build-app.sh
```

Creates `.build/release/RemoteDiff.app` and a `.zip` ready to share. On the target Mac, unzip and drag to `/Applications`. First launch: right-click → Open to bypass Gatekeeper (app is not notarized).

## Usage

1. Click **+** to create a connection and enter an SSH host
2. Add repositories with a path and git ref
3. Select a repo — auto-fetches the diff and displays in side-by-side mode
4. Use the segmented picker to switch between **Side by Side**, **Diff**, and **Full File** views
5. Use ↑/↓ buttons (or ⌘↑/⌘↓) to jump between changes
6. Toggle **Watch** for live change detection

## Project Structure

```
RemoteDiff/
├── Models/
│   ├── DiffModels.swift          # DiffLine, DiffHunk, FileDiff, SSHHost, RepoSelection
│   ├── DiffParser.swift          # Unified diff parser
│   ├── DisplayLineBuilder.swift  # Builds display lines for all view modes
│   ├── SSHConfig.swift           # ~/.ssh/config parser
│   └── ConnectionStore.swift     # Connection + Repository persistence
├── Services/
│   ├── SSHService.swift          # SSH execution, diff fetching, caching
│   ├── FileContentService.swift  # Full file content fetching for side-by-side
│   └── ControlMasterWatcher.swift # Persistent SSH + change polling
├── Views/
│   ├── CodePaneView.swift        # Unified code rendering component
│   ├── DiffView.swift            # View mode switching + file header
│   ├── SidebarView.swift         # Connection/repo browser + file list
│   ├── LiveStatusBar.swift       # Watcher status indicator
│   └── LanguageConfig.swift      # 30+ language definitions
├── ContentView.swift             # Main NavigationSplitView
└── RemoteDiffApp.swift           # App entry point
```

## Requirements

- macOS 13 Ventura or later
- SSH access to remote hosts (key-based auth recommended)
- Git installed on the remote server
