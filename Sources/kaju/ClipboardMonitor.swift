// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import KajuCore

/// Watches the clipboard so kaju knows when, and in which app, it last
/// changed, and which changes kaju made itself. Also writes and restores the
/// clipboard for paste-based delivery.
final class ClipboardMonitor {
    private let pb = NSPasteboard.general
    private var lastCount: Int
    private var ownCounts = Set<Int>()
    private(set) var lastChange: ClipboardPolicy.Change?
    private var timer: Timer?

    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init() {
        lastCount = pb.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let count = pb.changeCount
        guard count != lastCount else { return }
        lastCount = count
        lastChange = ClipboardPolicy.Change(
            count: count, time: Date(),
            frontmostBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            concealed: pb.types?.contains(Self.concealed) ?? false,
            ownWrite: ownCounts.contains(count))
    }

    var changeCount: Int { pb.changeCount }
    var text: String? { pb.string(forType: .string) }
    var isConcealed: Bool { pb.types?.contains(Self.concealed) ?? false }

    /// Put text on the clipboard as kaju's own write, hidden from clipboard managers.
    func writeOwn(_ s: String, hidden: Bool = true) {
        pb.clearContents()
        pb.setString(s, forType: .string)
        if hidden {
            pb.setString("", forType: Self.transient)
            pb.setString("", forType: Self.concealed)
        }
        markOwn()
    }

    /// Everything on the clipboard, all items and types, to restore later.
    func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
    }

    func restore(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        let objects: [NSPasteboardItem] = items.map { d in
            let item = NSPasteboardItem()
            for (t, data) in d { item.setData(data, forType: t) }
            return item
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
        markOwn()
    }

    private func markOwn() {
        ownCounts.insert(pb.changeCount)
        lastCount = pb.changeCount
        lastChange = ClipboardPolicy.Change(count: pb.changeCount, time: Date(), frontmostBundle: nil,
                                            concealed: false, ownWrite: true)
    }
}
