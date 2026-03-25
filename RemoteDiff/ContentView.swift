import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var sshService = SSHService()
    @StateObject private var watcher = ControlMasterWatcher()
    @StateObject private var store = ConnectionStore()
    @StateObject private var fileContentService = FileContentService()
    @ObservedObject var themeStore: ThemeStore
    @Binding var pendingDeepLink: DeepLink?

    @State private var selectedHost = ""
    @State private var repoPath = ""
    @State private var gitRef = "HEAD"
    @State private var includeStaged = false
    @State private var includeUntracked = false
    @State private var selectedFileID: FileDiff.ID?
    @State private var isWatching = false
    @State private var viewMode: DiffViewMode = .sideBySide
    @State private var selection: RepoSelection? = {
        guard let connStr = UserDefaults.standard.string(forKey: "lastConnectionID"),
              let repoStr = UserDefaults.standard.string(forKey: "lastRepoID"),
              let connID = UUID(uuidString: connStr),
              let repoID = UUID(uuidString: repoStr) else { return nil }
        return RepoSelection(connectionID: connID, repositoryID: repoID)
    }()

    private let hosts = SSHConfigParser.parse()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                sshService: sshService, watcher: watcher, store: store, hosts: hosts,
                selectedHost: $selectedHost, repoPath: $repoPath, gitRef: $gitRef,
                includeStaged: $includeStaged, includeUntracked: $includeUntracked,
                selectedFileID: $selectedFileID, isWatching: $isWatching, selection: $selection
            )
            .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 450)
        } detail: {
            VStack(spacing: 0) {
                DiffView(fileDiff: selectedFileDiff, host: selectedHost, repoPath: repoPath, gitRef: gitRef, theme: themeStore.currentTheme, viewMode: $viewMode, fileContentService: fileContentService)
                if isWatching || watcher.status != .idle {
                    LiveStatusBar(watcher: watcher)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onReceive(watcher.changeDetected) { fetchAndCache() }
        .onChange(of: selection) { persistSelection($0) }
        .onChange(of: selectedFileID) { _ in fetchFileContentIfNeeded() }
        .onChange(of: viewMode) { _ in fetchFileContentIfNeeded() }
        .onAppear { restoreLastSelection() }
        .onChange(of: pendingDeepLink) { link in
            if let link = link {
                handleDeepLink(link)
                pendingDeepLink = nil
            }
        }
        .background {
            Button("") { navigateFile(direction: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .hidden()
            Button("") { navigateFile(direction: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Computed

    private var navigationTitle: String {
        guard let sel = selection, let found = store.repository(id: sel.repositoryID) else {
            return "RemoteDiff"
        }
        return "RemoteDiff — \(found.connection.name) / \(found.repository.name)"
    }

    private var selectedFileDiff: FileDiff? {
        sshService.fileDiffs.first { $0.id == selectedFileID }
    }

    // MARK: - Actions

    private func fetchFileContentIfNeeded() {
        guard viewMode != .diff, let fileDiff = selectedFileDiff else { return }
        fileContentService.fetchFor(fileDiff: fileDiff, host: selectedHost, repoPath: repoPath, gitRef: gitRef)
    }

    private func fetchAndCache() {
        let previousName = selectedFileDiff?.displayName
        let repoID = selection?.repositoryID

        // Invalidate file content so it will be re-fetched after diff completes
        fileContentService.invalidate()

        sshService.fetchDiff(host: selectedHost, repoPath: repoPath, gitRef: gitRef,
                             includeStaged: includeStaged, includeUntracked: includeUntracked) {
            selectedFileID = sshService.fileDiffs.first(where: { $0.displayName == previousName })?.id
                ?? sshService.fileDiffs.first?.id
            if let repoID { sshService.saveToCache(repoID: repoID, selectedFileID: selectedFileID) }

            // Re-fetch file content for Side-by-Side / Full File modes
            fetchFileContentIfNeeded()
        }
    }

    private func navigateFile(direction: Int) {
        guard !sshService.fileDiffs.isEmpty,
              let idx = sshService.fileDiffs.firstIndex(where: { $0.id == selectedFileID }) else {
            selectedFileID = sshService.fileDiffs.first?.id
            return
        }
        let newIdx = idx + direction
        if sshService.fileDiffs.indices.contains(newIdx) {
            selectedFileID = sshService.fileDiffs[newIdx].id
        }
    }

    private func persistSelection(_ sel: RepoSelection?) {
        UserDefaults.standard.set(sel?.connectionID.uuidString, forKey: "lastConnectionID")
        UserDefaults.standard.set(sel?.repositoryID.uuidString, forKey: "lastRepoID")
    }

    private func handleDeepLink(_ link: DeepLink) {
        // Look for an existing connection+repo matching this deep link
        var matchedConnection: SavedConnection?
        var matchedRepo: SavedRepository?

        for conn in store.connections {
            if conn.host == link.host {
                if let repo = conn.repositories.first(where: { $0.repoPath == link.repoPath }) {
                    matchedConnection = conn
                    matchedRepo = repo
                    break
                }
                // Same host but different repo — remember the connection
                if matchedConnection == nil { matchedConnection = conn }
            }
        }

        // If no exact match, create connection + repo
        if matchedRepo == nil {
            if matchedConnection == nil {
                // Derive a friendly name from the host
                matchedConnection = store.addConnection(name: link.host, host: link.host)
            }

            // Derive repo name from the last path component
            let repoName = (link.repoPath as NSString).lastPathComponent
            matchedRepo = store.addRepository(
                to: matchedConnection!.id,
                name: repoName.isEmpty ? "Repository" : repoName,
                repoPath: link.repoPath,
                gitRef: link.gitRef
            )

            // Update flags
            if var repo = matchedRepo {
                repo.includeStaged = link.includeStaged
                repo.includeUntracked = link.includeUntracked
                store.updateRepository(repo, in: matchedConnection!.id)
                matchedRepo = repo
            }
        }

        guard let conn = matchedConnection ?? store.connection(for: matchedConnection!.id),
              let repo = matchedRepo else { return }

        // Save current results before switching
        if let prev = selection {
            sshService.saveToCache(repoID: prev.repositoryID, selectedFileID: selectedFileID)
        }

        // Select and load
        selection = RepoSelection(connectionID: conn.id, repositoryID: repo.id)
        selectedHost = conn.host
        repoPath = repo.repoPath
        gitRef = repo.gitRef
        includeStaged = repo.includeStaged
        includeUntracked = repo.includeUntracked

        // Immediately fetch the diff
        fetchAndCache()

        // Bring the app to front
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func restoreLastSelection() {
        guard let sel = selection, let found = store.repository(id: sel.repositoryID) else { return }
        let conn = found.connection
        let repo = found.repository

        selectedHost = conn.host
        repoPath = repo.repoPath
        gitRef = repo.gitRef
        includeStaged = repo.includeStaged
        includeUntracked = repo.includeUntracked

        if !conn.host.isEmpty && !repo.repoPath.isEmpty {
            fetchAndCache()
        }
    }
}
