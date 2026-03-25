import Foundation
import Combine

// MARK: - Cached Diff Result

struct CachedDiffResult {
    let fileDiffs: [FileDiff]
    let lastError: String?
    let selectedFileID: FileDiff.ID?
}

// MARK: - SSH Service

class SSHService: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var fileDiffs: [FileDiff] = []

    /// Per-repository in-memory cache of fetched diffs
    private var cache: [UUID: CachedDiffResult] = [:]

    // MARK: - Cache

    func saveToCache(repoID: UUID, selectedFileID: FileDiff.ID?) {
        cache[repoID] = CachedDiffResult(fileDiffs: fileDiffs, lastError: lastError, selectedFileID: selectedFileID)
    }

    /// Restores cached results. Returns the previously selected file ID, or nil if no cache.
    func restoreFromCache(repoID: UUID) -> FileDiff.ID? {
        guard let cached = cache[repoID] else {
            fileDiffs = []
            lastError = nil
            return nil
        }
        fileDiffs = cached.fileDiffs
        lastError = cached.lastError
        return cached.selectedFileID
    }

    func clearCache(repoID: UUID) {
        cache.removeValue(forKey: repoID)
    }

    // MARK: - Fetch Diff

    func fetchDiff(host: String, repoPath: String, gitRef: String,
                   includeStaged: Bool = false, includeUntracked: Bool = false,
                   completion: (() -> Void)? = nil) {
        isLoading = true
        lastError = nil

        let script = Self.buildDiffScript(repoPath: repoPath, gitRef: gitRef,
                                          includeStaged: includeStaged, includeUntracked: includeUntracked)

        Self.runSSHBash(host: host, script: script) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                switch result {
                case .success(let output):
                    self.fileDiffs = DiffParser.parse(output)
                    if self.fileDiffs.isEmpty && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.lastError = String(output.prefix(500))
                    }
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.fileDiffs = []
                }
                completion?()
            }
        }
    }

    // MARK: - Script Building

    /// Builds the bash script to run on the remote host.
    static func buildDiffScript(repoPath: String, gitRef: String,
                                includeStaged: Bool, includeUntracked: Bool) -> String {
        let isRange = gitRef.contains("..")
        let effectiveRef = (includeStaged && !isRange && gitRef.isEmpty) ? "HEAD" : gitRef

        var script = "cd \(repoPath) && git diff \(effectiveRef)"

        if includeUntracked && !isRange {
            script += "\n" + #"git ls-files --others --exclude-standard | while IFS= read -r f; do git diff --no-index /dev/null "$f" 2>/dev/null || true; done"#
        }

        return script
    }

    /// Builds the bash script for polling (lightweight --stat version).
    static func buildPollScript(repoPath: String, gitRef: String,
                                includeStaged: Bool, includeUntracked: Bool) -> String {
        let isRange = gitRef.contains("..")
        let effectiveRef = (includeStaged && !isRange && gitRef.isEmpty) ? "HEAD" : gitRef

        var script = "cd \(repoPath) && git diff --stat \(effectiveRef)"

        if includeUntracked && !isRange {
            script += "\necho ---untracked---\ngit ls-files --others --exclude-standard"
        }

        return script
    }

    // MARK: - SSH Execution

    /// Resolves the path to the bundled `remotediff-askpass` helper.
    /// Checks the app bundle Resources first, then falls back to the scripts/ dir next to the executable.
    static let askpassPath: String? = {
        // 1. Inside .app bundle: Contents/Resources/remotediff-askpass
        if let bundled = Bundle.main.path(forResource: "remotediff-askpass", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        // 2. Development: scripts/remotediff-askpass relative to executable
        if let execURL = Bundle.main.executableURL {
            let devPath = execURL
                .deletingLastPathComponent()  // .build/debug or MacOS/
                .deletingLastPathComponent()  // .build/ or Contents/
                .deletingLastPathComponent()  // project root or .app
                .appendingPathComponent("scripts/remotediff-askpass")
                .path
            if FileManager.default.isExecutableFile(atPath: devPath) {
                return devPath
            }
        }
        return nil
    }()

    /// Runs a bash script on a remote host by piping via stdin.
    /// This avoids shell quoting issues regardless of the remote user's login shell.
    /// Sets SSH_ASKPASS so password prompts appear as native macOS dialogs.
    static func runSSHBash(host: String, script: String,
                           extraArgs: [String] = [],
                           completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = extraArgs + [host, "bash"]

            // Set up SSH_ASKPASS so SSH can show a native macOS password dialog
            // when there's no TTY (always the case when launched via Process).
            var env = ProcessInfo.processInfo.environment
            if let askpass = askpassPath {
                env["SSH_ASKPASS"] = askpass
                env["SSH_ASKPASS_REQUIRE"] = "prefer"
                env["DISPLAY"] = ":0"  // SSH checks this before using askpass
            }
            process.environment = env

            let inPipe = Pipe()
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()

                if let data = script.data(using: .utf8) {
                    inPipe.fileHandleForWriting.write(data)
                }
                inPipe.fileHandleForWriting.closeFile()

                // Read before waiting to avoid pipe buffer deadlock
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

                process.waitUntilExit()

                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    completion(.success(stdout))
                } else {
                    let msg = stderr.isEmpty ? "SSH exited with code \(process.terminationStatus)" : stderr
                    completion(.failure(SSHError.commandFailed(code: process.terminationStatus, message: msg)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - SSH Error

enum SSHError: LocalizedError {
    case commandFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(_, let message): return message
        }
    }
}
