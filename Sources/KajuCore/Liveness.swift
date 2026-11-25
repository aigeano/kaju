// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// Decides whether Claude Code is the foreground program on a terminal.
///
/// This is kaju's main safety check: text is only typed and submitted into a
/// pane when Claude Code owns the pane's terminal in the foreground. If a shell
/// were in front instead, the quoted lines ("> ...") would run as redirections
/// and commands. Anything the check cannot place is refused.
public enum Liveness {
    /// True if `argv` (a process's full command line, split on spaces) is Claude Code.
    /// Accepts the native `claude` binary, or `node` running the claude-code
    /// package's entry script (npm installs).
    public static func isClaude(argv: [String]) -> Bool {
        guard let first = argv.first else { return false }
        let program = (first as NSString).lastPathComponent
        if program == "claude" { return true }
        if program == "node", argv.count > 1 {
            let script = argv[1]
            return script.contains("@anthropic-ai/claude-code")
                || (script as NSString).lastPathComponent == "claude"
        }
        return false
    }

    /// Parse `ps -t <tty> -o pid=,tpgid=,args=` output and decide whether the
    /// foreground process group leader is Claude Code.
    public static func claudeInForeground(psOutput: String) -> Bool {
        for row in psOutput.split(separator: "\n") {
            let parts = row.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, parts[0] == parts[1] else { continue }  // leader of the foreground group
            if isClaude(argv: parts[2].split(separator: " ").map(String.init)) { return true }
        }
        return false
    }

    /// Run `ps` for a terminal device such as "/dev/ttys002" and apply the check.
    public static func claudeInForeground(tty: String, shell: Shell = .system) -> Bool {
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        guard !name.isEmpty, let out = shell.run("/bin/ps", ["-t", name, "-o", "pid=,tpgid=,args="]) else {
            return false
        }
        return claudeInForeground(psOutput: out)
    }
}
