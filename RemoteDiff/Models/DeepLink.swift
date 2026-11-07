import Foundation

/// Represents a parsed deep link from the `remotediff://` URL scheme.
///
/// CLI usage: `remotediff host:path [--ref REF] [--staged] [--untracked]`
/// URL format: `remotediff://open?host=HOST&path=PATH&ref=HEAD&staged=1&untracked=1`
struct DeepLink: Equatable {
    let host: String
    let repoPath: String
    let gitRef: String
    let includeStaged: Bool
    let includeUntracked: Bool

    /// Allows plain refs, `HEAD~5`, `HEAD^` and a single `a..b` range. Rejects anything
    /// starting with `-` (option injection) or containing shell/whitespace characters.
    /// An empty `ref=` is rejected (omit the parameter to default to HEAD).
    static func isValidGitRef(_ ref: String) -> Bool {
        guard !ref.isEmpty, !ref.hasPrefix("-"),
              ref.range(of: "^[A-Za-z0-9._/~^@{}+-]+$", options: .regularExpression) != nil else {
            return false
        }
        return ref.components(separatedBy: "..").count - 1 <= 1
    }

    /// Allows `host`, `user@host` and bare IPv6 (`:`). The allowlist is the real defence: it keeps
    /// `%`, `/`, spaces and shell metacharacters out of the hostname so ssh_config expansions
    /// (`%h` in ProxyCommand/Match exec) can't be abused. `--` in `runSSHBash` additionally
    /// prevents option parsing. Note the CLI (scripts/remotediff) splits on the first `:` so
    /// cannot pass IPv6 hosts.
    static func isValidHost(_ host: String) -> Bool {
        !host.isEmpty && !host.hasPrefix("-")
            && host.range(of: "^([A-Za-z0-9._-]+@)?[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
    }

    /// Rejects empty paths and any control or format character (NUL, CR, LF, tab, RTL override…;
    /// `CharacterSet.controlCharacters` covers Cc and Cf) plus U+2028/U+2029, which could spoof
    /// extra lines in the confirmation dialog. Everything else is safe because every sink quotes
    /// the path and uses `cd --`.
    static func isValidRepoPath(_ path: String) -> Bool {
        !path.isEmpty && !path.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || $0 == "\u{2028}" || $0 == "\u{2029}"
        }
    }

    /// Parse a `remotediff://` URL into a DeepLink.
    /// Expected format: `remotediff://open?host=HOST&path=PATH&ref=HEAD&staged=1&untracked=1`
    static func parse(from url: URL) -> DeepLink? {
        guard url.scheme == "remotediff" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func value(for name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let host = value(for: "host"), !host.isEmpty,
              let path = value(for: "path"), !path.isEmpty else {
            return nil
        }

        let gitRef = value(for: "ref") ?? "HEAD"
        guard isValidHost(host), isValidGitRef(gitRef), isValidRepoPath(path) else {
            return nil
        }
        let staged = value(for: "staged") == "1"
        let untracked = value(for: "untracked") == "1"

        return DeepLink(
            host: host,
            repoPath: path,
            gitRef: gitRef,
            includeStaged: staged,
            includeUntracked: untracked
        )
    }
}
