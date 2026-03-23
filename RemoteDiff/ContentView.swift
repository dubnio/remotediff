import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var sshService = SSHService()
    @StateObject private var watcher = ControlMasterWatcher()
    @StateObject private var store = ConnectionStore()
    @StateObject private var fileContentService = FileContentService()
    @ObservedObject var themeStore: ThemeStore

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

        sshService.fetchDiff(host: selectedHost, repoPath: repoPath, gitRef: gitRef,
                             includeStaged: includeStaged, includeUntracked: includeUntracked) {
            selectedFileID = sshService.fileDiffs.first(where: { $0.displayName == previousName })?.id
                ?? sshService.fileDiffs.first?.id
            if let repoID { sshService.saveToCache(repoID: repoID, selectedFileID: selectedFileID) }
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
