// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// Decides whether the clipboard holds a selection the user just made in the
/// terminal, rather than something stale, unrelated or secret.
///
/// Claude Code copies the selection to the clipboard (with `pbcopy`) when the
/// user selects text in its full-screen mode, so the clipboard is how kaju
/// sees the selection in every terminal.
public enum ClipboardPolicy {
    /// A clipboard change observed by kaju's monitor.
    public struct Change: Equatable {
        public var count: Int
        public var time: Date
        /// Bundle id of the app in front when the change happened.
        public var frontmostBundle: String?
        /// True if the content was marked `org.nspasteboard.ConcealedType` (passwords).
        public var concealed: Bool
        /// True if kaju made this change itself.
        public var ownWrite: Bool

        public init(count: Int, time: Date, frontmostBundle: String?, concealed: Bool, ownWrite: Bool) {
            self.count = count
            self.time = time
            self.frontmostBundle = frontmostBundle
            self.concealed = concealed
            self.ownWrite = ownWrite
        }
    }

    /// Tiers that can read the pane's visible text (iTerm2, tmux, Terminal.app):
    /// accept the clipboard only if its start is visible in the pane.
    public static func acceptVisible(clipboard: String, visibleText: String, concealed: Bool) -> Bool {
        if concealed { return false }
        let head = String(Message.squash(clipboard).prefix(40))
        guard !head.isEmpty else { return false }
        return Message.squash(visibleText).contains(head)
    }

    /// Generic tier: accept the latest change only if it was made recently,
    /// while a terminal app was in front, not by kaju, and is not concealed.
    public static func acceptGeneric(last: Change?, currentCount: Int, now: Date,
                                     window: TimeInterval, terminalBundles: Set<String>) -> Bool {
        guard let c = last, c.count == currentCount else { return false }  // changed since we saw it
        if c.ownWrite || c.concealed { return false }
        guard let app = c.frontmostBundle, terminalBundles.contains(app) else { return false }
        return now.timeIntervalSince(c.time) <= window
    }
}
