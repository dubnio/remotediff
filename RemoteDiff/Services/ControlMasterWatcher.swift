import Foundation
import Combine

// MARK: - ControlMaster Watcher

/// Maintains a persistent SSH ControlMaster connection and polls for changes
/// by periodically running `git diff --stat` on the remote. When the stat output
/// changes, it publishes on `changeDetected` (debounced 800ms).
class ControlMasterWatcher: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case watching
        case error(String)
    }

    @Published var status: Status = .idle

    let changeDetected = PassthroughSubject<Void, Never>()

    private var pollTimer: Timer?
    private var masterProcess: Process?
    private var lastStatOutput: String = ""
    private var cancellables = Set<AnyCancellable>()
    private let rawChange = PassthroughSubject<Void, Never>()

    // Current watch configuration
    var host: String = ""
    private var repoPath: String = ""
    private var gitRef: String = "HEAD"
    private var includeStaged: Bool = false
    private var includeUntracked: Bool = false

    private var socketPath: String {
        "\(NSTemporaryDirectory())remotediff-ssh-\(host)"
    }

    init() {
        rawChange
            .debounce(for: .milliseconds(800), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.changeDetected.send() }
            .store(in: &cancellables)
    }

    deinit { stop() }

    // MARK: - Public

    func start(host: String, repoPath: String, gitRef: String,
               includeStaged: Bool = false, includeUntracked: Bool = false) {
        stop()

        self.host = host
        self.repoPath = repoPath
        self.gitRef = gitRef
        self.includeStaged = includeStaged
        self.includeUntracked = includeUntracked
        self.lastStatOutput = ""

        status = .connecting
        startMaster()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        terminateMaster()
        status = .idle
    }

    func reconnect() {
        start(host: host, repoPath: repoPath, gitRef: gitRef,
              includeStaged: includeStaged, includeUntracked: includeUntracked)
    }

    // MARK: - ControlMaster

    private func startMaster() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "ControlMaster=yes",
            "-o", "ControlPath=\(socketPath)",
            "-o", "ControlPersist=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-N",
            host
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            masterProcess = process
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.verifyMasterAndStartPolling()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.status = .error("Failed to start SSH: \(error.localizedDescription)")
            }
        }
    }

    private func verifyMasterAndStartPolling() {
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        check.arguments = ["-o", "ControlPath=\(socketPath)", "-O", "check", host]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice

        do {
            try check.run()
            check.waitUntilExit()

            DispatchQueue.main.async { [weak self] in
                if check.terminationStatus == 0 {
                    self?.status = .watching
                    self?.startPolling()
                } else {
                    self?.status = .error("ControlMaster socket not established")
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.status = .error("Failed to check master: \(error.localizedDescription)")
            }
        }
    }

    private func terminateMaster() {
        let exit = Process()
        exit.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        exit.arguments = ["-o", "ControlPath=\(socketPath)", "-O", "exit", host]
        exit.standardOutput = FileHandle.nullDevice
        exit.standardError = FileHandle.nullDevice
        try? exit.run()
        exit.waitUntilExit()

        masterProcess?.terminate()
        masterProcess = nil
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollForChanges()
        }
    }

    private func pollForChanges() {
        let script = SSHService.buildPollScript(
            repoPath: repoPath, gitRef: gitRef,
            includeStaged: includeStaged, includeUntracked: includeUntracked
        )
        let controlArgs = ["-o", "ControlPath=\(socketPath)"]

        SSHService.runSSHBash(host: host, script: script, extraArgs: controlArgs) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let output):
                    if output != self.lastStatOutput {
                        let isFirstPoll = self.lastStatOutput.isEmpty
                        self.lastStatOutput = output
                        if !isFirstPoll {
                            self.rawChange.send()
                        }
                    }
                case .failure:
                    self.status = .error("SSH poll failed — connection may have dropped")
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                }
            }
        }
    }
}
