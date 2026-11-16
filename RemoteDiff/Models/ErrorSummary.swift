import Foundation

/// Turns a failed ssh run (exit code + stderr) into a one-line, plain-language summary.
/// `SSHService.failureMessage` puts it on the first line of the error message; the views show
/// that line and keep the full text for the details sheet.
///
/// stderr is partly controlled by the remote (server banners, the repo's git config, shell rc
/// files), so the rules are strict: ssh's own failures only count when ssh itself failed
/// (exit 255) and only in ssh's own line formats; git rules only count when ssh succeeded and
/// the remote command failed (any other exit code).
enum ErrorSummary {
    static func summarize(stderr: String, exitCode: Int32) -> String {
        exitCode == 255 ? sshSummary(stderr) : remoteSummary(stderr)
    }

    private static func sshSummary(_ s: String) -> String {
        if line(s, #"Host key verification failed\."#) {
            if s.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") { return "Host key changed" }
            if s.contains("REVOKED HOST KEY") { return "Host key revoked" }
            return "Host key not known"
        }
        if line(s, #"[^\n]*: Permission denied \([a-z,-]+\)\."#)
            || line(s, #"Received disconnect from [^\n]*: Too many authentication failures[^\n]*"#) {
            return "Authentication failed"
        }
        if line(s, #"ssh: Could not resolve hostname [^\n]*"#) { return "Host not found" }
        if line(s, #"ssh: connect to host [^\n]* port \d+: [^\n]*"#)
            || line(s, #"kex_exchange_identification: [^\n]*"#)
            || line(s, #"Connection timed out during banner exchange"#)
            || line(s, #"Connection (closed|reset) by [^\n]* port \d+"#) {
            return "Couldn't connect to the host"
        }
        if line(s, #"Connection to [^\n]* closed by remote host\."#)
            || line(s, #"client_loop: send disconnect: [^\n]*"#)
            || line(s, #"mux_client_request_session: [^\n]*"#)
            || line(s, #"Control socket connect\([^\n]*"#) {
            return "Lost the connection to the host"
        }
        return "SSH failed"
    }

    private static func remoteSummary(_ s: String) -> String {
        if s.contains("detected dubious ownership in repository") {
            return "Git doesn't trust the repository's owner (safe.directory)"
        }
        if s.contains("not a git repository") { return "Not a git repository" }
        if line(s, #"[^\n]*git: (command )?not found"#) { return "git isn't installed on the host" }
        if line(s, #"[^\n]*cd: [^\n]*: No such file or directory"#) { return "Repository folder not found" }
        if s.contains("unknown revision") || s.contains("bad revision") { return "Git ref not found" }
        return "Command failed on the host"
    }

    /// True if some whole line of `text` (ignoring a trailing CR) matches `pattern`.
    private static func line(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + #"\r?$"#, options: .anchorsMatchLines) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
