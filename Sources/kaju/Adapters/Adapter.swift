// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import ApplicationServices
import KajuCore

/// The pane a comment belongs to, captured when the user presses the hotkey.
struct Target {
    /// Review key, stable for the pane (see the plan's restore rules).
    var key: String
    /// Name shown in the review panel header.
    var label: String
    var bundleID: String
    var pid: pid_t
    /// Terminal device of the pane, for the liveness check.
    var tty: String?
    /// On-screen window (CGWindowID), when known.
    var windowID: CGWindowID?
    /// Adapter-specific identifiers (iTerm2 session id, tmux pane id, ...).
    var ref: [String: String] = [:]
}

enum DeliveryMode {
    /// Paste, pause, press Return. Only after the liveness check passed.
    case submit
    /// Paste only; the user presses Return (Basic tier).
    case pasteOnly
}

enum DeliveryResult {
    case sent
    case pasted
    case refused(String)  // safety check failed; nothing was typed
    case failed(String)   // something technical went wrong
}

/// One terminal app. Methods are called off the main thread and may block briefly.
protocol TerminalAdapter: AnyObject {
    var name: String { get }
    var bundleIDs: Set<String> { get }
    /// The front pane of the app with this pid.
    func target(app: NSRunningApplication) -> Target?
    /// Where the selection ends on screen (Cocoa coordinates), if the terminal can tell.
    func selectionAnchor(_ t: Target, clipboard: String) -> NSPoint?
    /// Text currently visible in the pane, for the stale-clipboard check.
    func visibleText(_ t: Target) -> String?
    /// Frame of the target's window (Cocoa coordinates), for docking the review panel.
    func windowFrame(_ t: Target) -> NSRect?
    /// True while the target's tab is the selected one.
    func isTabSelected(_ t: Target) -> Bool
    /// True if Claude Code is the foreground program; nil if the adapter cannot tell.
    func isClaudeRunning(_ t: Target) -> Bool?
    /// Bring the target's window and tab to the front.
    func activate(_ t: Target)
    func deliver(_ text: String, to t: Target, mode: DeliveryMode) -> DeliveryResult
}

/// macOS helpers shared by adapters.
enum System {
    /// Height of the primary screen, to convert between top-left and Cocoa coordinates.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cocoaRect(fromTopLeft r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// On-screen layer-0 windows, front to back.
    static func windows() -> [[String: Any]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
    }

    /// Front window of a process: (id, Cocoa frame).
    static func frontWindow(pid: pid_t) -> (CGWindowID, NSRect)? {
        for w in windows() where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
            guard let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            return (id, cocoaRect(fromTopLeft: r))
        }
        return nil
    }

    static func frame(ofWindow id: CGWindowID) -> NSRect? {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] ?? []
        guard let b = list.first?[kCGWindowBounds as String] as? [String: CGFloat],
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        return cocoaRect(fromTopLeft: r)
    }

    /// The top layer-0 window that does not belong to kaju itself.
    static func topWindowIgnoringKaju() -> CGWindowID? {
        let me = ProcessInfo.processInfo.processIdentifier
        return windows().first { ($0[kCGWindowOwnerPID as String] as? pid_t) != me }?[kCGWindowNumber as String] as? CGWindowID
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Ask macOS to show the Accessibility prompt for kaju.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Title of the focused window of an app, via Accessibility.
    static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let w = win else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static func pasteKeystroke() { key(9, flags: .maskCommand) }   // ⌘V
    static func returnKeystroke() { key(36) }                      // Return

    static func activate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Wait until `condition` holds or the timeout passes.
    @discardableResult
    static func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return condition()
    }
}

/// Paste through the clipboard and the keyboard: save the clipboard, write the
/// message (hidden from clipboard managers), press ⌘V, restore the clipboard.
/// Must be called with the target window already in front.
enum PasteDelivery {
    static func paste(_ text: String, clipboard: ClipboardMonitor) {
        let saved = DispatchQueue.main.sync { clipboard.snapshot() }
        DispatchQueue.main.sync { clipboard.writeOwn(text) }
        System.pasteKeystroke()
        // The terminal reads the clipboard when it handles ⌘V; give it time before restoring.
        Thread.sleep(forTimeInterval: 0.35)
        DispatchQueue.main.sync { clipboard.restore(saved) }
    }
}
