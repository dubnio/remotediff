import Foundation

/// Fetches and caches full file content from remote for Full File / Side-by-Side views.
class FileContentService: ObservableObject {
    @Published var isLoading = false
    @Published var oldContent: String?
    @Published var newContent: String?
    @Published var loadError: String?
    private(set) var lastFileID: String?

    /// Invalidates cached content so the next `fetchFor` will re-fetch.
    /// Does NOT show a loading spinner or clear existing content — the old content
    /// remains visible until the fresh fetch completes (seamless refresh).
    func invalidate() {
        lastFileID = nil
    }

    /// Fetches content for the given file. Skips if already loaded for same file.
    func fetchFor(fileDiff: FileDiff, host: String, repoPath: String, gitRef: String) {
        // Already have content for this file
        if lastFileID == fileDiff.id && (newContent != nil || loadError != nil) { return }
        if lastFileID == fileDiff.id && isLoading { return }

        // Same file being refreshed (invalidated) — keep old content visible while fetching
        let isRefresh = (newContent != nil || oldContent != nil) && lastFileID == nil

        // New file — reset and fetch
        lastFileID = fileDiff.id
        if !isRefresh {
            oldContent = nil
            newContent = nil
        }
        loadError = nil
        isLoading = !isRefresh  // Don't show spinner for refreshes

        guard !host.isEmpty && !repoPath.isEmpty else {
            isLoading = false
            loadError = "No host or repo path configured"
            return
        }

        let newPath = fileDiff.isDeletedFile ? fileDiff.oldPath : fileDiff.newPath
        let oldPath = fileDiff.isNewFile ? nil : fileDiff.oldPath
        let ref = gitRef.isEmpty ? "HEAD" : gitRef
        let fileID = fileDiff.id

        var script = "cat '\(newPath)'"
        if let oldPath = oldPath {
            script += "\necho '<<<REMOTEDIFF_SEPARATOR>>>'"
            script += "\ngit show \(ref):'\(oldPath)' 2>/dev/null || echo ''"
        }
        script = "cd \(repoPath) && " + script

        SSHService.runSSHBash(host: host, script: script) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.lastFileID == fileID else { return }
                self.isLoading = false
                switch result {
                case .success(let output):
                    if oldPath != nil {
                        let parts = output.components(separatedBy: "<<<REMOTEDIFF_SEPARATOR>>>\n")
                        self.newContent = parts.first ?? ""
                        self.oldContent = parts.count > 1 ? parts[1] : ""
                    } else {
                        self.newContent = output
                        self.oldContent = ""
                    }
                case .failure(let error):
                    self.loadError = error.localizedDescription
                }
            }
        }
    }
}
