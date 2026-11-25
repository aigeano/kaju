// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import KajuCore

/// Basic tier: any terminal without a richer adapter (Ghostty, Warp, Alacritty, ...).
///
/// kaju cannot see which program runs in the window, so it never presses
/// Return here, and it always pastes the message as a single line with every
/// control character removed. A shell without bracketed paste would run each
/// line of a multi-line paste; a single line without a newline never runs.
/// (A window title is not proof of what is in the foreground: it can still
/// show Claude Code after Claude has exited.)
final class GenericAdapter: TerminalAdapter {
    let name = "generic"
    let clipboard: ClipboardMonitor
    /// Apps treated as terminals (also used by the clipboard policy).
    let bundleIDs: Set<String>

    static let knownTerminals: Set<String> = [
        "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "dev.warp.Warp", "org.alacritty",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
        "com.raphaelamorim.rio", "com.apple.Terminal", "com.googlecode.iterm2",
    ]

    init(clipboard: ClipboardMonitor, extraTerminals: Set<String> = []) {
        self.clipboard = clipboard
        self.bundleIDs = Self.knownTerminals.union(extraTerminals)
    }

    func target(app: NSRunningApplication) -> Target? {
        guard let bundle = app.bundleIdentifier, let (id, _) = System.frontWindow(pid: app.processIdentifier) else { return nil }
        let title = System.focusedWindowTitle(pid: app.processIdentifier) ?? ""
        let label = [app.localizedName ?? bundle, title].filter { !$0.isEmpty }.joined(separator: " · ")
        return Target(key: "generic:\(bundle):\(id)", label: label, bundleID: bundle,
                      pid: app.processIdentifier, tty: nil, windowID: id)
    }

    func selectionAnchor(_ t: Target, clipboard: String) -> NSPoint? { nil }
    func visibleText(_ t: Target) -> String? { nil }
    func windowFrame(_ t: Target) -> NSRect? { t.windowID.flatMap(System.frame(ofWindow:)) }
    func isTabSelected(_ t: Target) -> Bool { true }  // app-level visibility only
    func isClaudeRunning(_ t: Target) -> Bool? { nil }
    func activate(_ t: Target) { System.activate(pid: t.pid) }

    func deliver(_ text: String, to t: Target, mode: DeliveryMode) -> DeliveryResult {
        guard System.accessibilityTrusted else {
            DispatchQueue.main.async { System.requestAccessibility() }
            return .failed("kaju needs Accessibility permission to paste into \(t.label). Grant it in System Settings, then send again.")
        }
        System.activate(pid: t.pid)
        // The terminal must be the active app and the captured window its front window.
        guard System.wait(1.0, {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == t.pid
                && System.topWindowIgnoringKaju() == t.windowID
        }) else {
            return .refused("The window you commented on did not come to the front, so nothing was pasted.")
        }
        PasteDelivery.paste(Message.singleLine(text), clipboard: clipboard)
        return .pasted  // never Return in this tier
    }
}
