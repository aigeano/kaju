// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import CoreServices
import KajuCore

/// Terminal.app, through AppleScript (Automation permission). Delivery selects
/// the captured tab, pastes and presses Return (Accessibility permission),
/// and only after the liveness check passed.
final class TerminalAppAdapter: TerminalAdapter {
    let name = "Terminal.app"
    let bundleIDs: Set<String> = ["com.apple.Terminal"]
    let clipboard: ClipboardMonitor
    let shell: Shell

    init(clipboard: ClipboardMonitor, shell: Shell = .system) {
        self.clipboard = clipboard
        self.shell = shell
    }

    /// Why the last `target` failed, for the user (nil when it worked).
    private(set) var problem: String?

    /// Make sure kaju may control Terminal (Automation). Asks the user if needed and
    /// waits for the answer, so the AppleScript calls below never time out on the prompt.
    private func automationAllowed() -> Bool {
        var addr = AEAddressDesc()
        let id = "com.apple.Terminal"
        let made = id.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &addr) }
        guard made == noErr else { return false }
        defer { AEDisposeDesc(&addr) }
        let status = AEDeterminePermissionToAutomateTarget(&addr, AEEventClass(typeWildCard), AEEventID(typeWildCard), true)
        switch status {
        case noErr:
            return true
        case OSStatus(errAEEventNotPermitted):
            problem = "kaju is not allowed to control Terminal. Turn it on in System Settings › Privacy & Security › Automation › kaju › Terminal."
            return false
        default:
            problem = "Could not check kaju's permission to control Terminal (error \(status))."
            return false
        }
    }

    private func osa(_ script: String) -> String? {
        shell.run("/usr/bin/osascript", ["-e", script]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Run `body` with `w` and `t` bound to the window and tab whose tty matches.
    private func onTab(_ tty: String, _ body: String) -> String? {
        guard tty.range(of: #"^/dev/ttys[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return osa("""
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                \(body)
              end if
            end repeat
          end repeat
        end tell
        """)
    }

    func target(app: NSRunningApplication) -> Target? {
        problem = nil
        guard automationAllowed() else { return nil }
        guard let out = osa("""
        tell application "Terminal"
          set w to front window
          set t to selected tab of w
          return (id of w as text) & tab & (tty of t) & tab & (name of w)
        end tell
        """) else {
            problem = "Terminal did not answer kaju's request for the front tab."
            return nil
        }
        let f = out.components(separatedBy: "\t")
        guard f.count >= 3, let wid = UInt32(f[0]) else { return nil }
        // ttys are reused by newer tabs, so the key also names the window.
        return Target(key: "terminal:\(f[1]):\(wid)", label: f[2], bundleID: "com.apple.Terminal",
                      pid: app.processIdentifier, tty: f[1], windowID: wid)
    }

    /// True if a tab with this tty exists in the window with this id.
    func tabExists(tty: String, windowID: CGWindowID) -> Bool {
        onTab(tty, "if (id of w) is \(windowID) then return \"yes\"") == "yes"
    }

    func selectionAnchor(_ t: Target, clipboard: String) -> NSPoint? { nil }

    func visibleText(_ t: Target) -> String? {
        t.tty.flatMap { onTab($0, "return contents of t") }
    }

    func windowFrame(_ t: Target) -> NSRect? {
        guard let tty = t.tty, let out = onTab(tty, "return bounds of w") else { return nil }
        let n = out.components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard n.count == 4 else { return nil }
        return System.cocoaRect(fromTopLeft: CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1]))
    }

    func isTabSelected(_ t: Target) -> Bool {
        guard let tty = t.tty else { return false }
        return onTab(tty, "return ((selected of t) and (index of w is 1)) as text") == "true"
    }

    func isClaudeRunning(_ t: Target) -> Bool? {
        guard let tty = t.tty else { return false }
        return Liveness.claudeInForeground(tty: tty, shell: shell)
    }

    func activate(_ t: Target) {
        if let tty = t.tty { _ = onTab(tty, "set selected of t to true\nset index of w to 1") }
        System.activate(pid: t.pid)
    }

    func deliver(_ text: String, to t: Target, mode: DeliveryMode) -> DeliveryResult {
        guard System.accessibilityTrusted else {
            DispatchQueue.main.async { System.requestAccessibility() }
            return .failed("kaju needs Accessibility permission to type into Terminal. Grant it in System Settings, then send again.")
        }
        activate(t)
        guard System.wait(1.5, { self.isTabSelected(t) && NSWorkspace.shared.frontmostApplication?.processIdentifier == t.pid }) else {
            return .refused("Could not bring the Terminal tab you commented on to the front, so nothing was typed.")
        }
        PasteDelivery.paste(text, clipboard: clipboard)  // Terminal wraps it as a bracketed paste
        guard mode == .submit else { return .pasted }
        Thread.sleep(forTimeInterval: 0.2)
        // Check again right before Return: same tab in front, Claude Code still running.
        guard isTabSelected(t), NSWorkspace.shared.frontmostApplication?.processIdentifier == t.pid,
              isClaudeRunning(t) == true else {
            return .pasted  // pasted into Claude Code's prompt, not submitted
        }
        System.returnKeystroke()
        return .sent
    }
}
