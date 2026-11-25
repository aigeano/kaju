// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import KajuCore

/// tmux running inside a host terminal tab (iTerm2 or Terminal.app).
///
/// Used only when a tmux client is attached on the host tab's tty, so a
/// background tmux server never receives a comment. Window frame and
/// app-level visibility come from the host; the pane comes from tmux.
final class TmuxAdapter: TerminalAdapter {
    let name = "tmux"
    let bundleIDs: Set<String> = []
    let host: TerminalAdapter
    let hostTarget: Target
    let tmux: Tmux

    init(host: TerminalAdapter, hostTarget: Target, tmux: Tmux) {
        self.host = host
        self.hostTarget = hostTarget
        self.tmux = tmux
    }

    /// Wrap a host target if a tmux client is attached on its tty.
    static func wrap(_ host: TerminalAdapter, _ hostTarget: Target, tmux: Tmux?) -> (TmuxAdapter, Target)? {
        guard let tmux, let tty = hostTarget.tty, let client = tmux.client(onTTY: tty),
              let pane = tmux.activePane(client: client) else { return nil }
        let adapter = TmuxAdapter(host: host, hostTarget: hostTarget, tmux: tmux)
        var t = hostTarget
        t.key = "tmux:\(pane.address)"
        t.label = "tmux \(pane.address)"
        t.tty = pane.tty
        t.ref["tmuxPane"] = pane.id
        t.ref["tmuxClient"] = client
        return (adapter, t)
    }

    func target(app: NSRunningApplication) -> Target? { nil }  // created through wrap()
    func selectionAnchor(_ t: Target, clipboard: String) -> NSPoint? { nil }

    func visibleText(_ t: Target) -> String? {
        t.ref["tmuxPane"].flatMap { tmux.visibleText(paneID: $0) }
    }

    func windowFrame(_ t: Target) -> NSRect? { host.windowFrame(hostTarget) }

    /// Host tab selected AND the pane's tmux window is the active one.
    func isTabSelected(_ t: Target) -> Bool {
        guard host.isTabSelected(hostTarget), let id = t.ref["tmuxPane"], let pane = tmux.pane(id: id) else { return false }
        return pane.windowActive
    }

    func isClaudeRunning(_ t: Target) -> Bool? {
        guard let id = t.ref["tmuxPane"], let pane = tmux.pane(id: id) else { return false }
        return Liveness.claudeInForeground(tty: pane.tty, shell: tmux.shell)
    }

    func activate(_ t: Target) { host.activate(hostTarget) }

    func deliver(_ text: String, to t: Target, mode: DeliveryMode) -> DeliveryResult {
        guard let id = t.ref["tmuxPane"] else { return .failed("tmux pane unknown") }
        return tmux.deliver(text, paneID: id, submit: mode == .submit) ? (mode == .submit ? .sent : .pasted)
                                                                       : .failed("tmux could not paste into pane \(id).")
    }
}
