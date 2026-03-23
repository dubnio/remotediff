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
