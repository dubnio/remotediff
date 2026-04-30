import SwiftUI

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var sshService: SSHService
    @ObservedObject var watcher: ControlMasterWatcher
    @ObservedObject var store: ConnectionStore
    let hosts: [SSHHost]

    @Binding var selectedHost: String
    @Binding var repoPath: String
    @Binding var gitRef: String
    @Binding var includeStaged: Bool
    @Binding var includeUntracked: Bool
    @Binding var selectedFileID: FileDiff.ID?
    @Binding var isWatching: Bool
    @Binding var selection: RepoSelection?

    @State private var editConnectionName: String = ""
    @State private var editRepoName: String = ""
    @State private var isConnectionExpanded: Bool = false
    @State private var browserSize: BrowserSize = .medium
    @State private var remoteBranch: String = ""

    enum BrowserSize: CaseIterable {
        case small, medium, large

        var maxHeight: CGFloat {
            switch self {
            case .small: return 100
            case .medium: return 220
            case .large: return 400
            }
        }

        var icon: String {
            switch self {
            case .small: return "rectangle.compress.vertical"
            case .medium: return "rectangle.split.1x2"
            case .large: return "rectangle.expand.vertical"
            }
        }

        mutating func cycle() {
            switch self {
            case .small: self = .medium
            case .medium: self = .large
            case .large: self = .small
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            browserSection
            Divider()
            connectionSection
            Divider()
            fileListSection
        }
    }

    // MARK: - Browser Section

    private var browserSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Connections")
                    .font(.headline)
                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { browserSize.cycle() }
                } label: {
                    Image(systemName: browserSize.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Resize: \(String(describing: browserSize))")

                Button(action: addConnection) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Add new connection")
            }

            if store.connections.isEmpty {
                Text("No saved connections")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.connections) { conn in
                            ConnectionSection(
                                connection: conn,
                                selection: selection,
                                onSelectRepo: { repo in selectRepo(repo, in: conn) },
                                onAddRepo: { addRepo(to: conn) },
                                onDeleteConnection: { deleteConnection(conn) },
                                onDeleteRepo: { repo in deleteRepo(repo, from: conn) }
                            )
                        }
                    }
                }
                .frame(maxHeight: browserSize.maxHeight)
            }
        }
        .padding()
    }

    // MARK: - Connection Details Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selection != nil {
                // Header with expand/collapse
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isConnectionExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isConnectionExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 10)
                            Text("Connection")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if hasUnsavedChanges {
                        Button("Save") { saveChanges() }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                // Expanded: full editing fields
                if isConnectionExpanded {
                    TextField("Connection name", text: $editConnectionName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveChanges() }

                    Picker("Host", selection: $selectedHost) {
                        Text("Select host…").tag("")
                        ForEach(hosts) { host in
                            Text(host.displayName).tag(host.name)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Or enter host…", text: $selectedHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Divider()

                    Text("Repository")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Repository name", text: $editRepoName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveChanges() }

                    TextField("Repository path", text: $repoPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    TextField("Git ref (e.g. HEAD, main..feature)", text: $gitRef)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Toggle("Include staged changes", isOn: $includeStaged)
                        .font(.caption)
                    Toggle("Include untracked files", isOn: $includeUntracked)
                        .font(.caption)
                }

                // Current remote branch
                if !remoteBranch.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(remoteBranch)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            fetchRemoteBranch()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh branch")
                    }
                }

                // Action buttons — always visible
                HStack {
                    Button(action: fetchDiff) {
                        HStack(spacing: 4) {
                            if sshService.isLoading {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 14, height: 14)
                                Text("Fetching…")
                            } else {
                                Label("Fetch Diff", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedHost.isEmpty || repoPath.isEmpty || sshService.isLoading)
                    .keyboardShortcut("r", modifiers: .command)

                    Spacer()

                    Toggle(isOn: $isWatching) {
                        Label("Watch", systemImage: "eye")
                    }
                    .toggleStyle(.button)
                    .onChange(of: isWatching) { newValue in
                        if newValue {
                            watcher.start(host: selectedHost, repoPath: repoPath, gitRef: gitRef, includeStaged: includeStaged, includeUntracked: includeUntracked)
                        } else {
                            watcher.stop()
                        }
                    }
                    .disabled(selectedHost.isEmpty || repoPath.isEmpty)
                }
            } else {
                Text("Connection")
                    .font(.headline)
                Text("Select a repository or add a connection to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }

            if let error = sshService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }
        }
        .padding()
    }

    // MARK: - File List

    private var fileListSection: some View {
        Group {
            if sshService.fileDiffs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No files")
                        .foregroundColor(.secondary)
                    Text("Fetch a diff to see changed files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                let groups = FileGroup.group(sshService.fileDiffs)
                List(selection: $selectedFileID) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.files) { file in
                                FileRow(file: file, showDirectory: false)
                                    .tag(file.id)
                            }
                        } header: {
                            FileGroupHeader(group: group)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - Actions

    private func addConnection() {
        let conn = store.addConnection()
        if let repo = store.addRepository(to: conn.id) {
            selectRepo(repo, in: store.connection(for: conn.id)!)
        }
    }

    private func addRepo(to connection: SavedConnection) {
        if let repo = store.addRepository(to: connection.id) {
            selectRepo(repo, in: store.connection(for: connection.id)!)
        }
    }

    private func selectRepo(_ repo: SavedRepository, in connection: SavedConnection) {
        // Save current results before switching
        if let prev = selection {
            sshService.saveToCache(repoID: prev.repositoryID, selectedFileID: selectedFileID)
        }

        selection = RepoSelection(connectionID: connection.id, repositoryID: repo.id)
        selectedHost = connection.host
        repoPath = repo.repoPath
        gitRef = repo.gitRef
        includeStaged = repo.includeStaged
        includeUntracked = repo.includeUntracked
        editConnectionName = connection.name
        editRepoName = repo.name
        remoteBranch = ""

        // Fetch current branch from remote
        fetchRemoteBranch()

        // Restore cached results, or auto-fetch if no cache and connection is ready
        let cachedFileID = sshService.restoreFromCache(repoID: repo.id)
        selectedFileID = cachedFileID

        // Restart watcher for the new repo, or stop if not configured
        if isWatching {
            if !connection.host.isEmpty && !repo.repoPath.isEmpty {
                watcher.start(host: connection.host, repoPath: repo.repoPath, gitRef: repo.gitRef, includeStaged: repo.includeStaged, includeUntracked: repo.includeUntracked)
            } else {
                isWatching = false
                watcher.stop()
            }
        }

        // Auto-fetch when there's no cached data and the repo is configured
        if cachedFileID == nil && sshService.fileDiffs.isEmpty
            && !connection.host.isEmpty && !repo.repoPath.isEmpty {
            fetchDiff()
        }
    }

    private func deleteConnection(_ connection: SavedConnection) {
        if selection?.connectionID == connection.id {
            selection = nil
            selectedHost = ""
            repoPath = ""
            gitRef = "HEAD"
            sshService.fileDiffs = []
            selectedFileID = nil
        }
        for repo in connection.repositories {
            sshService.clearCache(repoID: repo.id)
        }
        store.deleteConnection(connection)
    }

    private func deleteRepo(_ repo: SavedRepository, from connection: SavedConnection) {
        if selection?.repositoryID == repo.id {
            selection = nil
            sshService.fileDiffs = []
            selectedFileID = nil
        }
        sshService.clearCache(repoID: repo.id)
        store.deleteRepository(repo, from: connection.id)
    }

    private func fetchDiff() {
        saveChanges()
        fetchRemoteBranch()

        let previousSelectedName = sshService.fileDiffs.first(where: { $0.id == selectedFileID })?.displayName
        let repoID = selection?.repositoryID

        sshService.fetchDiff(host: selectedHost, repoPath: repoPath, gitRef: gitRef, includeStaged: includeStaged, includeUntracked: includeUntracked) { [self] in
            if let name = previousSelectedName,
               let match = sshService.fileDiffs.first(where: { $0.displayName == name }) {
                selectedFileID = match.id
            } else {
                selectedFileID = sshService.fileDiffs.first?.id
            }
            // Cache the fresh results
            if let repoID = repoID {
                sshService.saveToCache(repoID: repoID, selectedFileID: selectedFileID)
            }
        }
    }

    private func saveChanges() {
        guard let sel = selection else { return }

        if var conn = store.connection(for: sel.connectionID) {
            conn.name = editConnectionName.trimmingCharacters(in: .whitespaces).isEmpty ? conn.name : editConnectionName
            conn.host = selectedHost
            store.updateConnection(conn)
        }

        var repo = SavedRepository(id: sel.repositoryID, name: editRepoName, repoPath: repoPath, gitRef: gitRef, includeStaged: includeStaged, includeUntracked: includeUntracked)
        if editRepoName.trimmingCharacters(in: .whitespaces).isEmpty {
            if let existing = store.repository(id: sel.repositoryID) {
                repo.name = existing.repository.name
            }
        }
        store.updateRepository(repo, in: sel.connectionID)
    }

    private func fetchRemoteBranch() {
        guard !selectedHost.isEmpty && !repoPath.isEmpty else {
            remoteBranch = ""
            return
        }
        let script = "cd \(repoPath) && git rev-parse --abbrev-ref HEAD"
        SSHService.runSSHBash(host: selectedHost, script: script) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let output):
                    remoteBranch = output.trimmingCharacters(in: .whitespacesAndNewlines)
                case .failure:
                    remoteBranch = ""
                }
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let sel = selection,
              let found = store.repository(id: sel.repositoryID) else { return false }
        let conn = found.connection
        let repo = found.repository
        return conn.name != editConnectionName ||
               conn.host != selectedHost ||
               repo.name != editRepoName ||
               repo.repoPath != repoPath ||
               repo.gitRef != gitRef ||
               repo.includeStaged != includeStaged ||
               repo.includeUntracked != includeUntracked
    }
}

// MARK: - Connection Section (disclosure group)

struct ConnectionSection: View {
    let connection: SavedConnection
    let selection: RepoSelection?
    let onSelectRepo: (SavedRepository) -> Void
    let onAddRepo: () -> Void
    let onDeleteConnection: () -> Void
    let onDeleteRepo: (SavedRepository) -> Void

    @State private var isExpanded = true
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Connection header
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Image(systemName: "server.rack")
                    .foregroundColor(isConnectionSelected ? .accentColor : .secondary)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 0) {
                    Text(connection.name)
                        .font(.system(.body).weight(.semibold))
                        .lineLimit(1)
                    Text(connection.host.isEmpty ? "No host set" : connection.host)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onAddRepo) {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add repository to this connection")

                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.4))
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Remove connection")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isConnectionSelected ? Color.accentColor.opacity(0.06) : Color.clear)
            )

            if isExpanded {
                ForEach(connection.repositories) { repo in
                    RepositoryRow(
                        repository: repo,
                        isSelected: selection?.repositoryID == repo.id,
                        onSelect: { onSelectRepo(repo) },
                        onDelete: { onDeleteRepo(repo) }
                    )
                }
            }
        }
        .alert("Delete Connection", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDeleteConnection() }
        } message: {
            Text("Delete \"\(connection.name)\" and all its repositories? This cannot be undone.")
        }
    }

    private var isConnectionSelected: Bool {
        selection?.connectionID == connection.id
    }
}

// MARK: - Repository Row

struct RepositoryRow: View {
    let repository: SavedRepository
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cylinder.split.1x2")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.caption2)

            VStack(alignment: .leading, spacing: 0) {
                Text(repository.name)
                    .font(.system(.callout).weight(.medium))
                    .lineLimit(1)
                Text(repository.repoPath.isEmpty ? "No path set" : repository.repoPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(repository.gitRef)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))

            Button { showDeleteConfirmation = true } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.4))
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Remove repository")
        }
        .padding(.leading, 28)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .alert("Delete Repository", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Delete \"\(repository.name)\"? This cannot be undone.")
        }
    }
}

// MARK: - File Group

/// A group of changed files that share the same parent directory.
/// Used by the sidebar to render directory headers above the files.
struct FileGroup: Identifiable {
    let directory: String     // e.g. "app/core/tests" or "" for root
    let files: [FileDiff]

    var id: String { directory }

    /// Pretty display path with breadcrumb separators, e.g. "app › core › tests".
    /// Returns "/" for root-level files.
    var displayDirectory: String {
        if directory.isEmpty { return "/" }
        return directory.split(separator: "/").joined(separator: " › ")
    }

    /// Groups files by parent directory, preserving the original order of first
    /// appearance for both directories and the files within them.
    static func group(_ files: [FileDiff]) -> [FileGroup] {
        var order: [String] = []
        var buckets: [String: [FileDiff]] = [:]
        for file in files {
            let dir = (file.displayName as NSString).deletingLastPathComponent
            if buckets[dir] == nil {
                order.append(dir)
                buckets[dir] = []
            }
            buckets[dir]?.append(file)
        }
        return order.map { FileGroup(directory: $0, files: buckets[$0] ?? []) }
    }
}

// MARK: - File Group Header

/// Section header shown above a group of files sharing the same directory.
struct FileGroupHeader: View {
    let group: FileGroup

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(group.displayDirectory)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Text("\(group.files.count)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

// MARK: - File Row

struct FileRow: View {
    let file: FileDiff
    /// When false, the inline directory path is hidden (used when the parent
    /// section already shows a directory header).
    var showDirectory: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon)
                .foregroundColor(fileIconColor)
                .font(.caption)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if showDirectory, let dir = directoryPath, !dir.isEmpty {
                    Text(dir)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            let stats = countStats()
            if stats.additions > 0 {
                Text("+\(stats.additions)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.green)
            }
            if stats.deletions > 0 {
                Text("-\(stats.deletions)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var fileName: String {
        (file.displayName as NSString).lastPathComponent
    }

    private var directoryPath: String? {
        let dir = (file.displayName as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }

    private var fileIcon: String {
        if file.isBinary { return "doc.zipper" }
        if file.isNewFile { return "plus.circle.fill" }
        if file.isDeletedFile { return "minus.circle.fill" }
        if file.isRenamed { return "arrow.right.circle.fill" }
        return "doc.text"
    }

    private var fileIconColor: Color {
        if file.isNewFile { return .green }
        if file.isDeletedFile { return .red }
        if file.isRenamed { return .orange }
        if file.isBinary { return .orange }
        return .secondary
    }

    private func countStats() -> (additions: Int, deletions: Int) {
        var add = 0, del = 0
        for hunk in file.hunks {
            for line in hunk.lines {
                switch line.type {
                case .addition: add += 1
                case .deletion: del += 1
                default: break
                }
            }
        }
        return (add, del)
    }
}
