// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import KajuCore

/// The floating comment input. It opens next to the selection (or at the
/// mouse pointer), shows the captured quote, and stays open until the comment
/// is finished (⏎ / ⌘⏎) or cleared (Esc). Drag it by its top line.
final class CommentInput: NSObject, NSTextFieldDelegate {
    enum Action { case send, add, addAndSend }
    struct Result { var comment: String; var action: Action; var tag: String; var quote: String }

    private let width: CGFloat = 640
    let panel: InputPanel
    private let box = DragBox()
    private let ears = EarsView()
    private let preview = PassLabel(labelWithString: "")
    private let hints = PassLabel(labelWithString: "")
    let field = NSTextField()
    private let tagChip = NSButton()
    private let reviewChip = NSButton()
    private let send = NSButton()
    private let guide = PassLabel(wrappingLabelWithString: CommentInput.guideText)
    private var monitor: Any?

    private let tags: [String]
    private var tag = 0
    /// Comments already in this pane's open review (0 if none).
    private(set) var pending: Int
    private var review: Bool
    private(set) var quote: String
    private var showGuide = UserDefaults.standard.bool(forKey: "showKeyGuide")
    private let onDone: (Result?) -> Void
    var tabShown = true
    var appShown = true

    static let guideText = """
    ⏎       send the comment, or add it to the review
    ⇧⏎      new line
    ⇥       start / cancel a review (collect comments, send together)
    ⇧⇥      tag: fix · question · nit
    ⌘⏎      add this comment and send the whole review
    esc     close and clear the comment
            (clicking the terminal leaves it open: click it to go on)
    drag    move this input by its top line
    ⌘/      show / hide this guide

    Review panel
    click   show a card in full        ✎ / double-click   edit
    ×       remove a comment           drag header        move the panel
    Send    send all and end review    Discard (2 clicks) drop the review
    """

    init(anchor: NSPoint?, quote: String, pending: Int, tags: [String], onDone: @escaping (Result?) -> Void) {
        self.quote = quote
        self.pending = pending
        self.review = pending > 0
        self.tags = [""] + tags
        self.onDone = onDone
        let at = anchor ?? NSEvent.mouseLocation
        var origin = NSPoint(x: at.x + 8, y: at.y - 4)
        let screen = NSScreen.screens.first { $0.frame.contains(at) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - 200)
        panel = InputPanel(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: 60)),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.background.cgColor
        box.layer?.cornerRadius = 16
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.ginger.cgColor
        box.toolTip = "Drag to move"
        panel.contentView = box

        preview.font = Theme.mono(11)
        preview.textColor = Theme.faint
        preview.lineBreakMode = .byTruncatingTail
        hints.font = NSFont.systemFont(ofSize: 10.5)
        hints.textColor = Theme.faint
        hints.alignment = .right
        guide.font = Theme.mono(11)
        guide.textColor = NSColor(white: 0.62, alpha: 1)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.mono(13)
        field.textColor = Theme.text
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = self

        for (b, action) in [(tagChip, #selector(cycleTag)), (reviewChip, #selector(toggleReview))] {
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 12
            b.layer?.borderWidth = 1
            b.target = self
            b.action = action
        }
        tagChip.toolTip = "Tag this comment (⇧⇥)"
        send.isBordered = false
        send.wantsLayer = true
        send.layer?.backgroundColor = Theme.ginger.cgColor
        send.layer?.cornerRadius = 14
        send.target = self
        send.action = #selector(enter)

        for v in [preview, hints, ears, field, tagChip, reviewChip, send, guide] { box.addSubview(v) }
        showQuote()
        refresh()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.panel, e.modifierFlags.contains(.command) else { return e }
            if e.keyCode == 36 { self.finish(self.review ? .addAndSend : .send); return nil }   // ⌘⏎
            if e.charactersIgnoringModifiers == "/" {                                            // ⌘/
                self.showGuide.toggle()
                UserDefaults.standard.set(self.showGuide, forKey: "showKeyGuide")
                self.layout()
                return nil
            }
            return e
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
    }

    /// A new selection while open: take its quote and come back to the front.
    func focus(quote q: String) {
        if !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { quote = q; showQuote() }
        tabShown = true
        applyVisibility()
        show()
        refocus()
    }

    func setPending(_ n: Int) {
        pending = n
        if n > 0 { review = true }
        refresh()
    }

    func applyVisibility() {
        if tabShown && appShown { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    private func showQuote() {
        let q = Message.squash(quote)
        preview.stringValue = q.isEmpty ? "(no selection: general comment)" : "› " + q
    }

    /// Lay out top-down; the field grows with its text, up to 8 lines; the bottom edge stays put.
    private func layout() {
        let pad: CGFloat = 12, rowY: CGFloat = 34, chipW: CGFloat = 104, tagW: CGFloat = 84, fieldX: CGFloat = 36
        let fieldW = width - fieldX - 44 - chipW - tagW - 16
        let need = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: fieldW, height: 1000)).height
        let fieldH = min(max(18, need), 8 * 17)
        var height = rowY + max(fieldH, 18) + 12
        guide.isHidden = !showGuide
        if showGuide {
            guide.preferredMaxLayoutWidth = width - 72
            let gh = guide.fittingSize.height
            guide.frame = NSRect(x: 36, y: height + 2, width: width - 72, height: gh)
            height += gh + 14
        }
        hints.sizeToFit()
        hints.frame = NSRect(x: width - pad - hints.frame.width - 4, y: 10, width: hints.frame.width + 4, height: 16)
        preview.frame = NSRect(x: 36, y: 10, width: hints.frame.minX - 36 - 12, height: 16)
        ears.frame = NSRect(x: 12, y: rowY - 1, width: 18, height: 18)
        field.frame = NSRect(x: fieldX, y: rowY, width: fieldW, height: fieldH)
        tagChip.frame = NSRect(x: width - 44 - chipW - 8 - tagW, y: rowY - 3, width: tagW, height: 24)
        reviewChip.frame = NSRect(x: width - 44 - chipW, y: rowY - 3, width: chipW, height: 24)
        send.frame = NSRect(x: width - 36, y: rowY - 5, width: 28, height: 28)
        var f = panel.frame
        f.size.height = height
        panel.setFrame(f, display: true)
        box.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func refresh() {
        let hint = pending > 0 ? "Add to review · ⏎ add" : review ? "Start a review · ⏎ add" : "Comment · ⏎ send"
        field.placeholderAttributedString = NSAttributedString(
            string: hint, attributes: [.foregroundColor: Theme.faint, .font: Theme.mono(13)])
        hints.stringValue = (pending > 0 ? "⌘⏎ add & send all" : review ? "⇥ cancel review" : "⇥ start a review")
            + " · ⇧⇥ tag · ⌘/ all keys"
        style(reviewChip, pending > 0 ? "● review · \(pending)" : review ? "● review" : "○ review", on: review)
        reviewChip.toolTip = pending > 0 ? "Review open: send or discard it from the side panel"
                                         : "Collect comments and send them together (⇥)"
        style(tagChip, tag == 0 ? "# tag" : "# " + tags[tag], on: tag != 0)
        send.attributedTitle = NSAttributedString(string: review ? "+" : "↑", attributes: [
            .foregroundColor: NSColor.black, .font: NSFont.systemFont(ofSize: 14, weight: .bold)])
        send.toolTip = review ? "Add to review" : "Send to Claude Code"
        layout()
    }

    private func style(_ b: NSButton, _ title: String, on: Bool) {
        b.layer?.backgroundColor = on ? Theme.ginger.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        b.layer?.borderColor = (on ? Theme.ginger : Theme.faint).cgColor
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: on ? Theme.ginger : Theme.faint, .font: Theme.mono(11, .semibold)])
    }

    /// Return focus to the field without selecting the typed text.
    private func refocus() {
        if field.currentEditor() != nil { return }
        panel.makeFirstResponder(field)
        let end = (field.stringValue as NSString).length
        field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
    }

    @objc private func toggleReview() {
        if pending == 0 { review.toggle(); refresh() }
        refocus()
    }

    @objc private func cycleTag() {
        tag = (tag + 1) % tags.count
        refresh()
        refocus()
    }

    @objc private func enter() { finish(review ? .add : .send) }

    private func finish(_ action: Action) {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty only makes sense as "send the open review as it is".
        if text.isEmpty && !(action == .addAndSend && pending > 0) { return }
        close()
        onDone(Result(comment: text, action: action, tag: tags[tag], quote: quote))
    }

    func controlTextDidChange(_ n: Notification) { layout() }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
                layout()
            } else {
                enter()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            onDone(nil)
            return true
        case #selector(NSResponder.insertTab(_:)):
            toggleReview()
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            cycleTag()
            return true
        default:
            return false
        }
    }
}

final class InputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Background that drags its window.
final class DragBox: NSView {
    override var isFlipped: Bool { true }
    override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) }
}

/// Label that lets clicks fall through to a DragBox behind it.
final class PassLabel: NSTextField {
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
}
