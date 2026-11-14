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

    // MARK: - Shell Quoting

    /// POSIX single-quote escaping: safe to interpolate into any sh/bash script.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Like `shellQuote`, but keeps a leading `~`, `~/` or `~user/` unquoted so tilde expansion still works.
    static func shellQuotePath(_ path: String) -> String {
        if path == "~" { return "~" }
        if path.hasPrefix("~/") { return "~/" + shellQuote(String(path.dropFirst(2))) }
        if let range = path.range(of: "^~[A-Za-z0-9._-]+(/|$)", options: .regularExpression) {
            let matched = String(path[range])
            if matched.hasSuffix("/") {
                let user = String(matched.dropLast())
                let rest = String(path[range.upperBound...])
                return rest.isEmpty ? user : user + "/" + shellQuote(rest)
            }
            return matched
        }
        return shellQuote(path)
    }

    // MARK: - Script Building

    /// Returns `""` or `" 'ref'"` — the quoted ref argument for `git diff`.
    private static func diffRefArgument(gitRef: String, includeStaged: Bool) -> String {
        let isRange = gitRef.contains("..")
        let effectiveRef = (includeStaged && !isRange && gitRef.isEmpty) ? "HEAD" : gitRef
        return effectiveRef.isEmpty ? "" : " " + shellQuote(effectiveRef)
    }

    /// Builds the bash script to run on the remote host.
    static func buildDiffScript(repoPath: String, gitRef: String,
                                includeStaged: Bool, includeUntracked: Bool) -> String {
        let isRange = gitRef.contains("..")
        let refArg = diffRefArgument(gitRef: gitRef, includeStaged: includeStaged)
        var script = "cd -- \(shellQuotePath(repoPath)) && git diff\(refArg) --"

        if includeUntracked && !isRange {
            script += "\n" + #"git ls-files --others --exclude-standard | while IFS= read -r f; do git diff --no-index -- /dev/null "$f" 2>/dev/null || true; done"#
        }

        return script
    }

    /// Builds the bash script for polling (lightweight --stat version).
    static func buildPollScript(repoPath: String, gitRef: String,
                                includeStaged: Bool, includeUntracked: Bool) -> String {
        let isRange = gitRef.contains("..")
        let refArg = diffRefArgument(gitRef: gitRef, includeStaged: includeStaged)
        var script = "cd -- \(shellQuotePath(repoPath)) && git diff --stat\(refArg) --"

        if includeUntracked && !isRange {
            script += "\necho ---untracked---\ngit ls-files --others --exclude-standard"
        }

        return script
    }

    /// Builds the script that reads the current branch name.
    static func buildBranchScript(repoPath: String) -> String {
        "cd -- \(shellQuotePath(repoPath)) && git rev-parse --abbrev-ref HEAD"
    }

    /// Builds the script that prints the new file content, and (when `oldPath` is given) a
    /// separator followed by the old content from `git show ref:oldPath`.
    static func buildFileContentScript(repoPath: String, gitRef: String,
                                       newPath: String, oldPath: String?) -> String {
        let ref = gitRef.isEmpty ? "HEAD" : gitRef
        var script = "cat -- \(shellQuote(newPath))"
        if let oldPath = oldPath {
            script += "\necho '<<<REMOTEDIFF_SEPARATOR>>>'"
            script += "\ngit show \(shellQuote(ref + ":" + oldPath)) 2>/dev/null || echo ''"
        }
        return "cd -- \(shellQuotePath(repoPath)) && " + script
    }

    // MARK: - Authentication Options

    /// UserDefaults key holding the hosts the user has explicitly allowed to use
    /// password / keyboard-interactive authentication. Every other host is key-only,
    /// so a hostile or unknown host can never show a password prompt.
    static let passwordAuthHostsKey = "passwordAuthHosts"

    static var passwordAuthHosts: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: passwordAuthHostsKey) ?? [])
    }

    static func setPasswordAuth(allowed: Bool, forHost host: String) {
        var hosts = passwordAuthHosts
        if allowed { hosts.insert(host) } else { hosts.remove(host) }
        UserDefaults.standard.set(Array(hosts).sorted(), forKey: passwordAuthHostsKey)
    }

    /// ssh options that refuse unknown or changed host keys, so a first connection can never be
    /// accepted through an askpass "Are you sure you want to continue connecting?" dialog.
    static let hostKeyOptionArgs = ["-o", "StrictHostKeyChecking=yes"]

    /// ssh options that restrict authentication to keys unless `host` is in `allowedHosts`.
    static func authOptionArgs(host: String, allowedHosts: Set<String>) -> [String] {
        allowedHosts.contains(host) ? [] : ["-o", "KbdInteractiveAuthentication=no", "-o", "PasswordAuthentication=no"]
    }

    /// Full ssh argv for `runSSHBash`. Host-key and auth options come first so nothing in
    /// `extraArgs` can override them (ssh keeps the first value of an option). A command-line
    /// `-o` also beats ~/.ssh/config, which is intended.
    /// `--` ends option parsing so a host string can never be read as an ssh option.
    static func sshArguments(host: String, extraArgs: [String], allowedHosts: Set<String>) -> [String] {
        hostKeyOptionArgs + authOptionArgs(host: host, allowedHosts: allowedHosts) + extraArgs + ["--", host, "bash"]
    }

    /// Extra guidance appended to ssh errors when authentication was denied for a host
    /// that is not allowed to use password / keyboard-interactive auth.
    static func authFailureHint(stderr: String, exitCode: Int32, host: String, allowedHosts: Set<String>) -> String? {
        guard exitCode == 255, !allowedHosts.contains(host),
              let regex = try? NSRegularExpression(pattern: #"Permission denied \(([^)]*)\)"#),
              let match = regex.firstMatch(in: stderr, range: NSRange(stderr.startIndex..., in: stderr)),
              let range = Range(match.range(at: 1), in: stderr) else { return nil }
        let methods = stderr[range].split(separator: ",").map(String.init)
        guard methods.contains("password") || methods.contains("keyboard-interactive") else { return nil }
        return "Password and keyboard-interactive authentication are disabled for this host. If you trust it and it needs a password or 2FA, turn on \"Allow password authentication for this host\" in the connection editor."
    }

    /// Extra guidance appended to ssh errors when the host key is unknown or has changed.
    static func hostKeyFailureHint(stderr: String, exitCode: Int32, host: String) -> String? {
        guard exitCode == 255, stderr.contains("Host key verification failed.") else { return nil }
        if stderr.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
            return "The host key for this host does not match the one saved in known_hosts. The server may have been reinstalled, or someone may be intercepting the connection. Check with the server's owner before removing the old key; the ssh message above names the file and line."
        }
        if stderr.contains("REVOKED HOST KEY") {
            return "This host's key is marked as revoked in known_hosts, so RemoteDiff will not connect. Check with the server's owner."
        }
        // StrictHostKeyChecking=ask overrides an accept-new / yes / no setting in ~/.ssh/config,
        // so Terminal always shows the fingerprint and asks.
        let plain = host.range(of: #"^[A-Za-z0-9][A-Za-z0-9._@-]*$"#, options: .regularExpression) != nil
        let command = "ssh -o StrictHostKeyChecking=ask " + (plain ? host : "-- " + shellQuote(host))
        return "RemoteDiff only connects to hosts whose key is already in known_hosts. To add this host's key, run the command below in Terminal, check that the fingerprint matches the server's, answer yes, then try again:\n" + "    " + command
    }

    /// Environment for ssh processes: SSH_ASKPASS so passphrase (and, if enabled, password)
    /// prompts appear as native macOS dialogs when there's no TTY (always the case with Process).
    static func sshEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let askpass = askpassPath {
            env["SSH_ASKPASS"] = askpass
            env["SSH_ASKPASS_REQUIRE"] = "prefer"
            env["DISPLAY"] = ":0"  // SSH checks this before using askpass
        }
        return env
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
    /// Sets SSH_ASKPASS so key passphrase (and, if enabled, password) prompts appear as native macOS dialogs.
    /// Password and keyboard-interactive auth are disabled unless the host is in `passwordAuthHosts`.
    static func runSSHBash(host: String, script: String,
                           extraArgs: [String] = [],
                           completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let allowed = passwordAuthHosts
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = sshArguments(host: host, extraArgs: extraArgs, allowedHosts: allowed)
            process.environment = sshEnvironment()

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
                    var msg = stderr.isEmpty ? "SSH exited with code \(process.terminationStatus)" : stderr
                    if let hint = authFailureHint(stderr: stderr, exitCode: process.terminationStatus, host: host, allowedHosts: allowed) {
                        msg += "\n" + hint
                    }
                    if let hint = hostKeyFailureHint(stderr: stderr, exitCode: process.terminationStatus, host: host) {
                        msg += "\n" + hint
                    }
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
