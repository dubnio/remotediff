import Foundation

// MARK: - Saved Connection (SSH host)

struct SavedConnection: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var repositories: [SavedRepository] = []
}

// MARK: - Saved Repository (git repo under a connection)

struct SavedRepository: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var repoPath: String
    var gitRef: String
    var includeStaged: Bool
    var includeUntracked: Bool

    init(id: UUID = UUID(), name: String = "New Repository", repoPath: String = "",
         gitRef: String = "HEAD", includeStaged: Bool = true, includeUntracked: Bool = true) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.gitRef = gitRef
        self.includeStaged = includeStaged
        self.includeUntracked = includeUntracked
    }

    // Handles missing keys when decoding older saved data
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        repoPath = try c.decode(String.self, forKey: .repoPath)
        gitRef = try c.decode(String.self, forKey: .gitRef)
        includeStaged = try c.decodeIfPresent(Bool.self, forKey: .includeStaged) ?? false
        includeUntracked = try c.decodeIfPresent(Bool.self, forKey: .includeUntracked) ?? false
    }
}

// MARK: - Connection Store

class ConnectionStore: ObservableObject {
    @Published var connections: [SavedConnection] = []

    private static let storageKey = "savedConnections_v2"

    init() {
        load()
    }

    // MARK: - Persistence

    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SavedConnection].self, from: data) else {
            return
        }
        connections = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    // MARK: - Connection CRUD

    @discardableResult
    func addConnection(name: String = "New Connection", host: String = "") -> SavedConnection {
        let conn = SavedConnection(name: name, host: host)
        connections.append(conn)
        save()
        return conn
    }

    func updateConnection(_ connection: SavedConnection) {
        guard let i = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[i] = connection
        save()
    }

    func deleteConnection(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        save()
    }

    // MARK: - Repository CRUD

    @discardableResult
    func addRepository(to connectionID: UUID, name: String = "New Repository",
                       repoPath: String = "", gitRef: String = "HEAD") -> SavedRepository? {
        guard let i = connections.firstIndex(where: { $0.id == connectionID }) else { return nil }
        let repo = SavedRepository(name: name, repoPath: repoPath, gitRef: gitRef)
        connections[i].repositories.append(repo)
        save()
        return repo
    }

    func updateRepository(_ repo: SavedRepository, in connectionID: UUID) {
        guard let ci = connections.firstIndex(where: { $0.id == connectionID }),
              let ri = connections[ci].repositories.firstIndex(where: { $0.id == repo.id }) else { return }
        connections[ci].repositories[ri] = repo
        save()
    }

    func deleteRepository(_ repo: SavedRepository, from connectionID: UUID) {
        guard let ci = connections.firstIndex(where: { $0.id == connectionID }) else { return }
        connections[ci].repositories.removeAll { $0.id == repo.id }
        save()
    }

    // MARK: - Lookups

    func connection(for id: UUID) -> SavedConnection? {
        connections.first { $0.id == id }
    }

    func repository(id repoID: UUID) -> (connection: SavedConnection, repository: SavedRepository)? {
        for conn in connections {
            if let repo = conn.repositories.first(where: { $0.id == repoID }) {
                return (conn, repo)
            }
        }
        return nil
    }
}
