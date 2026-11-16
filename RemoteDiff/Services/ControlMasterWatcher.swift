import Foundation
import Combine

// MARK: - ControlMaster Watcher

/// Polls for changes through the shared app-owned SSH master (`SSHConnectionManager`)
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
    private var lastStatOutput: String = ""
    /// Bumped on every start/stop so polls from a previous watch are discarded.
    private var generation = 0
    private var pollInFlight = false
    private var cancellables = Set<AnyCancellable>()
    private let rawChange = PassthroughSubject<Void, Never>()

    // Current watch configuration
    var host: String = ""
    private var repoPath: String = ""
    private var gitRef: String = "HEAD"
    private var includeStaged: Bool = false
    private var includeUntracked: Bool = false

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
        generation += 1
        pollInFlight = false

        self.host = host
        self.repoPath = repoPath
        self.gitRef = gitRef
        self.includeStaged = includeStaged
        self.includeUntracked = includeUntracked
        self.lastStatOutput = ""

        status = .connecting
        pollForChanges()  // the first poll also opens the shared master (and authenticates)
    }

    /// Stops polling. The shared master stays open: other fetches use it too.
    func stop() {
        generation += 1
        pollTimer?.invalidate()
        pollTimer = nil
        status = .idle
    }

    /// Restarts the watch. A dead master is reopened by `runSSHBash` itself; a healthy one is kept.
    func reconnect() {
        start(host: host, repoPath: repoPath, gitRef: gitRef,
              includeStaged: includeStaged, includeUntracked: includeUntracked)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollForChanges()
        }
    }

    private func pollForChanges() {
        guard !pollInFlight else { return }
        pollInFlight = true
        let gen = generation
        let script = SSHService.buildPollScript(
            repoPath: repoPath, gitRef: gitRef,
            includeStaged: includeStaged, includeUntracked: includeUntracked
        )
        let mayOpen = status != .watching  // only the first poll may connect; later ones never re-authenticate
        SSHService.runSSHBash(host: host, script: script,
                              shouldRun: { [weak self] in self?.generation == gen },
                              mayOpenConnection: mayOpen) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard gen == self.generation else { return }
                self.pollInFlight = false

                switch result {
                case .success(let output):
                    if self.status != .watching {
                        self.status = .watching
                        self.startPolling()
                    }
                    if output != self.lastStatOutput {
                        let isFirstPoll = self.lastStatOutput.isEmpty
                        self.lastStatOutput = output
                        if !isFirstPoll {
                            self.rawChange.send()
                        }
                    }
                case .failure(let error):
                    if case SSHError.cancelled = error { return }
                    self.status = .error(error.localizedDescription)
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                }
            }
        }
    }
}
