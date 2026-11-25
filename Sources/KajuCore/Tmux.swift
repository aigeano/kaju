// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// tmux support. tmux is never targeted on its own: it is used only when a
/// tmux client is attached on the tty of the terminal tab the user is in, so a
/// background tmux server can never receive a comment by accident.
public struct Tmux {
    public var path: String
    public var socket: String?
    public var shell: Shell

    public init(path: String, socket: String? = nil, shell: Shell = .system) {
        self.path = path
        self.socket = socket
        self.shell = shell
    }

    /// Find tmux: the configured path, else the usual Homebrew and system locations.
    public static func locate(configured: String?, fileExists: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
        let candidates = [configured, "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux", "/usr/bin/tmux"]
        return candidates.compactMap { $0 }.first(where: fileExists)
    }

    func run(_ args: [String], input: String? = nil) -> String? {
        let base = socket.map { ["-S", $0] } ?? []
        return shell.run(path, base + args, input: input)
    }

    /// A pane as kaju sees it.
    public struct Pane: Equatable {
        public var id: String         // "%3"
        public var tty: String        // "/dev/ttys007"
        public var address: String    // "work:1.0" (session:window.pane), stable across server restarts
        public var windowActive: Bool
        public var title: String
    }

    static let paneFormat = "#{pane_id}\t#{pane_tty}\t#{session_name}:#{window_index}.#{pane_index}\t#{window_active}\t#{pane_title}"

    public static func parsePane(_ line: String) -> Pane? {
        let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 5, f[0].hasPrefix("%") else { return nil }
        return Pane(id: f[0], tty: f[1], address: f[2], windowActive: f[3] == "1", title: f[4])
    }

    /// The client attached on a host terminal tty, if any (e.g. "/dev/ttys004").
    public func client(onTTY tty: String) -> String? {
        guard let out = run(["list-clients", "-F", "#{client_tty}"]) else { return nil }
        return out.split(separator: "\n").map(String.init).first { $0 == tty }
    }

    /// The active pane shown by a client.
    public func activePane(client: String) -> Pane? {
        run(["display-message", "-p", "-c", client, Tmux.paneFormat]).flatMap {
            Tmux.parsePane($0.trimmingCharacters(in: .newlines))
        }
    }

    /// A pane by id, to re-check it at send time.
    public func pane(id: String) -> Pane? {
        run(["display-message", "-p", "-t", id, Tmux.paneFormat]).flatMap {
            Tmux.parsePane($0.trimmingCharacters(in: .newlines))
        }
    }

    /// Text visible in a pane, for the stale-clipboard check.
    public func visibleText(paneID: String) -> String? {
        run(["capture-pane", "-p", "-J", "-t", paneID])
    }

    /// Bracketed paste of `text` into a pane, then (if `submit`) Enter after a short pause.
    public func deliver(_ text: String, paneID: String, submit: Bool) -> Bool {
        let buffer = "kaju"
        guard run(["load-buffer", "-b", buffer, "-"], input: text) != nil,
              run(["paste-buffer", "-p", "-d", "-b", buffer, "-t", paneID]) != nil else { return false }
        if submit {
            Thread.sleep(forTimeInterval: 0.2)
            return run(["send-keys", "-t", paneID, "Enter"]) != nil
        }
        return true
    }
}
