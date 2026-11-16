import Foundation

// MARK: - SSH Connection Manager

/// Owns one ssh ControlMaster per host (keyed by the exact host string, so `user@h` and `h` get
/// separate masters). Every ssh the app runs goes through the master's socket, so a host
/// authenticates once (one Touch ID / password) instead of once per operation, and the app closes
/// every connection it opened. The master gets its own `ControlPath` and `ControlPersist=no`, so it
/// lives and dies with the ssh process this class started.
///
/// Lifecycle: a master is started on first use (on SSHService's serial ssh queue, so its prompts
/// never overlap others) and is reused while its process runs and its socket exists. It is closed
/// at app quit (`closeAll`), when password auth changes for the host, and when the last connection
/// using the host is deleted or edited (`closeMaster`). `removeLeftovers` cleans up after a crashed
/// instance at launch. A failed start is remembered so requests queued before it fail fast instead
/// of prompting again. The user's own ControlMasters are never used, checked or closed.
final class SSHConnectionManager {
    static let shared = SSHConnectionManager()

    /// Parent of the per-process socket directories.
    static let rootDirectory: String = NSTemporaryDirectory() + "rdcm"

    /// App-private directory for this process's master sockets (one per pid, so two running
    /// instances never touch each other's masters). Kept short: Unix socket paths must be
    /// < 104 bytes and ssh appends a ~17-char temporary suffix while creating the socket.
    static let socketDirectory: String = rootDirectory + "/" + String(getpid())

    private var socketCounter = 0

    /// Returns a fresh socket path for a new master. Names are a counter, so the host never appears
    /// in the path and a dying old master can't unlink a newer master's socket.
    func nextSocketPath() -> String {
        lock.lock(); defer { lock.unlock() }
        socketCounter += 1
        return Self.socketDirectory + "/m\(socketCounter)"
    }

    /// Session-shape options. `ForkAfterAuthentication=no`: a config `ForkAfterAuthentication yes` would
    /// background the master (our Process would exit) and make clients fail. The others stop a config
    /// `RequestTTY` / `RemoteCommand` / `SessionType` from changing what we run.
    static let sessionOptionArgs = ["-o", "ForkAfterAuthentication=no", "-o", "RequestTTY=no", "-o", "RemoteCommand=none"]

    /// ssh argv for the master. Host-key and auth options come first (ssh keeps the first value).
    /// `ControlPersist=no` overrides a `ControlPersist` in ~/.ssh/config, which would background
    /// the master and make our Process exit.
    static func masterArguments(host: String, socketPath: String, allowedHosts: Set<String>) -> [String] {
        SSHService.hostKeyOptionArgs + SSHService.authOptionArgs(host: host, allowedHosts: allowedHosts)
            + SSHService.connectionOptionArgs + SSHService.forwardingOptionArgs + sessionOptionArgs + [
                "-o", "ControlMaster=yes",
                "-o", "ControlPath=\(socketPath)",
                "-o", "ControlPersist=no",
                // askpass can't abort a login: Cancel counts as a wrong password and ssh asks again
                // (3 times by default). One dialog per attempt; Fetch again to retry.
                "-o", "NumberOfPasswordPrompts=1",
                "-N",
                "--", host
            ]
    }

    /// Extra ssh args for clients: use the master's socket only. If the socket is missing ssh falls
    /// back to a direct connection, so every auth method and the user's proxy settings are turned
    /// off too: the fallback fails at once instead of prompting (Touch ID / password). `ProxyCommand=false`
    /// (not `none`) keeps ssh on the mux path and makes the fallback fail locally in ~10 ms instead of
    /// attempting a direct TCP connection; `ProxyJump=none` stops the user's jump host being used.
    /// (Only clients: the master keeps the user's proxy.)
    static func clientArguments(socketPath: String) -> [String] {
        ["-o", "ControlPath=\(socketPath)", "-o", "ControlMaster=no", "-o", "BatchMode=yes",
         "-o", "IdentityAgent=none", "-o", "PubkeyAuthentication=no",
         "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
         "-o", "GSSAPIAuthentication=no", "-o", "HostbasedAuthentication=no",
         "-o", "ProxyCommand=false", "-o", "ProxyJump=none", "-o", "SessionType=default"] + sessionOptionArgs
    }

    /// True if a request made at `requestedAt` should fail with the last master failure instead of
    /// starting another master: it was queued before that failure, so it would only re-prompt.
    static func shouldFailFast(requestedAt: TimeInterval, lastFailureAt: TimeInterval?) -> Bool {
        guard let lastFailureAt else { return false }
        return requestedAt < lastFailureAt
    }

    // MARK: - Registry

    private final class MasterEntry {
        let process: Process
        let socketPath: String
        let errPipe = Pipe()
        /// Signalled once when the master's stderr reaches EOF.
        let stderrEOF = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var buffer = Data()
        private var _closed = false

        init(process: Process, socketPath: String) {
            self.process = process
            self.socketPath = socketPath
        }

        var closed: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _closed }
        }

        /// Marks the entry closed; returns false if it already was (so closing is idempotent).
        func markClosed() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if _closed { return false }
            _closed = true
            return true
        }

        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            buffer.append(data)
            if buffer.count > 65_536 { buffer = buffer.suffix(65_536) }
        }

        var stderrText: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: buffer, as: UTF8.self)
        }
    }

    private let lock = NSLock()
    private var masters: [String: MasterEntry] = [:]
    private var lastFailure: [String: (time: TimeInterval, error: Error)] = [:]
    private var shuttingDown = false

    /// How long to wait for the master to authenticate. Deliberately long: the user may be
    /// answering a Touch ID or password dialog; sshd's LoginGraceTime ends a stuck login anyway.
    private static let readinessTimeout: TimeInterval = 150

    // MARK: - Ensure

    /// Returns the socket path of a live master for `host`, starting one if needed.
    /// `requestedAt` is when the caller asked: if a master for this host failed after that, the
    /// request fails with the same error without starting ssh (see `shouldFailFast`).
    /// Synchronous and slow (it waits for authentication): only call it on SSHService's serial ssh queue.
    func ensureMaster(host: String, requestedAt: TimeInterval, mayStart: Bool = true) -> Result<String, Error> {
        lock.lock()
        if shuttingDown {
            lock.unlock()
            return .failure(SSHError.cancelled)
        }
        let existing = masters[host]
        if let existing, !existing.closed, existing.process.isRunning,
           FileManager.default.fileExists(atPath: existing.socketPath) {
            lock.unlock()
            return .success(existing.socketPath)
        }
        if !mayStart {
            // Background polls must not open a connection (and prompt) the user didn't ask for.
            lock.unlock()
            return .failure(SSHError.commandFailed(code: 255, message: "Lost the connection to this host. Click Reconnect to connect again."))
        }
        if let failure = lastFailure[host], Self.shouldFailFast(requestedAt: requestedAt, lastFailureAt: failure.time) {
            lock.unlock()
            return .failure(failure.error)
        }
        if let existing, masters[host] === existing { masters.removeValue(forKey: host) }
        lock.unlock()
        if let existing { close(existing) }

        let socketPath = nextSocketPath()
        do {
            try FileManager.default.createDirectory(atPath: Self.socketDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return fail(host: host, entry: nil, error: error)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.environment = SSHService.sshEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        let entry = MasterEntry(process: process, socketPath: socketPath)
        process.standardError = entry.errPipe
        entry.errPipe.fileHandleForReading.readabilityHandler = { [weak entry] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                entry?.stderrEOF.signal()
            } else {
                entry?.append(data)
            }
        }

        // Registered before the process starts, so a concurrent close finds it.
        lock.lock()
        if shuttingDown {
            lock.unlock()
            entry.errPipe.fileHandleForReading.readabilityHandler = nil
            return .failure(SSHError.cancelled)
        }
        masters[host] = entry
        lock.unlock()

        // The password setting is read after registering, so a `setPasswordAuth` -> `closeMaster`
        // landing anywhere after this point terminates this master (checked after `run()`).
        let allowed = SSHService.passwordAuthHosts
        process.arguments = Self.masterArguments(host: host, socketPath: socketPath, allowedHosts: allowed)

        do {
            try process.run()
        } catch {
            entry.errPipe.fileHandleForReading.readabilityHandler = nil
            return fail(host: host, entry: entry, error: error)
        }
        if entry.closed {
            process.terminate()
            return .failure(SSHError.commandFailed(code: 255, message: "SSH connection was closed"))
        }

        // Wait for readiness with backoff.
        let deadline = ProcessInfo.processInfo.systemUptime + Self.readinessTimeout
        var delay = 0.1
        while true {
            if Self.control("check", socketPath: socketPath) == 0 {
                lock.lock()
                lastFailure.removeValue(forKey: host)
                lock.unlock()
                return .success(socketPath)
            }
            if entry.closed {
                process.terminate()
                return .failure(SSHError.commandFailed(code: 255, message: "SSH connection was closed"))
            }
            if !process.isRunning { break }
            let stderr = entry.stderrText
            // Only ssh's own message about our socket (a server banner must not trigger this).
            if stderr.contains("disabling multiplexing"), stderr.contains(socketPath) {
                process.terminate()
                close(entry)
                let message = SSHService.failureMessage(stderr: stderr, exitCode: 255, host: host, allowedHosts: allowed)
                return fail(host: host, entry: entry, error: SSHError.commandFailed(code: 255, message: message))
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                process.terminate()
                close(entry)
                var message = "Timed out waiting for SSH authentication"
                if !stderr.isEmpty { message += "\n" + stderr }
                return fail(host: host, entry: entry, error: SSHError.commandFailed(code: 255, message: message))
            }
            Thread.sleep(forTimeInterval: delay)
            delay = min(delay * 2, 1.0)
        }

        // The master exited before becoming ready: report its stderr like a failed command.
        process.waitUntilExit()
        _ = entry.stderrEOF.wait(timeout: .now() + 1)  // a ProxyCommand child may hold the pipe open
        let code = process.terminationStatus
        let message = SSHService.failureMessage(stderr: entry.stderrText, exitCode: code, host: host, allowedHosts: allowed)
        close(entry)
        return fail(host: host, entry: entry, error: SSHError.commandFailed(code: code, message: message))
    }

    /// Records a failed master start (so requests queued behind it fail fast) and drops the entry.
    private func fail(host: String, entry: MasterEntry?, error: Error) -> Result<String, Error> {
        lock.lock()
        if let entry, masters[host] === entry { masters.removeValue(forKey: host) }
        lastFailure[host] = (ProcessInfo.processInfo.systemUptime, error)
        lock.unlock()
        return .failure(error)
    }

    /// True if the registered master for `host` is running and answers `-O check`.
    func isMasterUsable(host: String) -> Bool {
        lock.lock()
        let entry = masters[host]
        lock.unlock()
        guard let entry, !entry.closed, entry.process.isRunning else { return false }
        return Self.control("check", socketPath: entry.socketPath) == 0
    }

    // MARK: - Closing

    /// Closes the master for `host`. Thread-safe and quick; does not touch the ssh queue.
    func closeMaster(host: String) {
        lock.lock()
        let entry = masters.removeValue(forKey: host)
        lastFailure.removeValue(forKey: host)
        lock.unlock()
        if let entry { close(entry) }
    }

    /// Closes every master and refuses new ones (app quit).
    func closeAll() {
        lock.lock()
        shuttingDown = true
        let all = Array(masters.values)
        masters.removeAll()
        lock.unlock()
        all.forEach(close)
        try? FileManager.default.removeItem(atPath: Self.socketDirectory)
    }

    /// At launch: stops masters left behind by crashed previous runs and deletes their sockets.
    /// Only touches `rdcm/<pid>` directories of pids that are no longer running (never ours, never a
    /// live instance's), plus the old watcher masters (`$TMPDIR/remotediff-ssh-*`, which ran with
    /// ControlPersist=yes and so outlive the app). Blocks on `ssh -O exit`: call off the main thread.
    func removeLeftovers() {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: Self.rootDirectory)) ?? [] {
            let path = Self.rootDirectory + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                  let pid = Int32(name), pid != getpid() else { continue }
            guard kill(pid, 0) != 0, errno == ESRCH else { continue }
            for socket in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
                _ = Self.control("exit", socketPath: path + "/" + socket)
            }
            try? fm.removeItem(atPath: path)
        }
        let tmp = NSTemporaryDirectory()
        for name in (try? fm.contentsOfDirectory(atPath: tmp)) ?? [] where name.hasPrefix("remotediff-ssh-") {
            let path = tmp + name
            _ = Self.control("exit", socketPath: path)
            try? fm.removeItem(atPath: path)
        }
    }

    /// Never waits: our Process is the master (ControlPersist=no, ForkAfterAuthentication=no), and
    /// SIGTERM makes ssh remove its socket. Safe to call from the main thread; idempotent.
    private func close(_ entry: MasterEntry) {
        guard entry.markClosed() else { return }
        entry.errPipe.fileHandleForReading.readabilityHandler = nil
        if entry.process.isRunning { entry.process.terminate() }
        try? FileManager.default.removeItem(atPath: entry.socketPath)
    }

    /// Runs `ssh -O <operation>` against a socket; returns the exit status (-1 if ssh could not start).
    /// `-F /dev/null`: this needs nothing from ~/.ssh/config, and a `Match exec` there would
    /// otherwise run on every check.
    private static func control(_ operation: String, socketPath: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        // The host argument is irrelevant when ControlPath is a literal path.
        process.arguments = ["-F", "/dev/null", "-o", "ControlPath=\(socketPath)", "-O", operation, "--", "rdcm"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
