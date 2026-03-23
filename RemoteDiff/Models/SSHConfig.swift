import Foundation

// MARK: - SSH Config Parser

struct SSHConfigParser {
    /// Parses ~/.ssh/config and returns an array of SSHHost entries.
    /// Skips wildcard hosts (Host *) and pattern hosts.
    static func parse() -> [SSHHost] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = home + "/.ssh/config"
        return parse(filePath: configPath)
    }

    static func parse(filePath: String) -> [SSHHost] {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }
        return parse(content: content)
    }

    static func parse(content: String) -> [SSHHost] {
        var hosts: [SSHHost] = []
        var currentName: String?
        var currentHostname: String?
        var currentUser: String?
        var currentPort: Int?
        var currentIdentityFile: String?

        func flushHost() {
            if let name = currentName, !name.contains("*"), !name.contains("?") {
                hosts.append(SSHHost(
                    name: name,
                    hostname: currentHostname,
                    user: currentUser,
                    port: currentPort,
                    identityFile: currentIdentityFile.map { expandTilde($0) }
                ))
            }
            currentName = nil
            currentHostname = nil
            currentUser = nil
            currentPort = nil
            currentIdentityFile = nil
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: " ", maxSplits: 1).map { String($0) }
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "host":
                flushHost()
                currentName = value
            case "hostname":
                currentHostname = value
            case "user":
                currentUser = value
            case "port":
                currentPort = Int(value)
            case "identityfile":
                currentIdentityFile = value
            default:
                break
            }
        }

        flushHost()
        return hosts
    }

    /// Expands ~ to user's home directory
    static func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + String(path.dropFirst(1))
        }
        return path
    }
}
