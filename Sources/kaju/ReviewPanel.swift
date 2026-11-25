// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import KajuCore

/// The review panel, docked on the right edge of the terminal window while a
/// review is open. Every comment is a compact card: click to show it in full,
/// ✎ or double-click to edit, × to remove. Drag the header to move the panel.
final class ReviewPanel: NSObject, NSTextFieldDelegate, NSGestureRecognizerDelegate, NSWindowDelegate {
    private(set) var items: [Annotation]
    private var open = Set<Int>()
    private var editingIndex: Int?
    private var editor: NSTextField?
    private var editorHeight: NSLayoutConstraint?
    private var discardArmed = false
    private let host: NSRect
    private let label: String
    let panel: TrayPanel
    private var topRight: NSPoint
    private var placing = false
    var tabShown = true
    var appShown = true

    /// Called after every change (to save the review).
    var onChange: (([Annotation]) -> Void)?
    var onSend: (([Annotation]) -> Void)?
    var onDiscard: (() -> Void)?
    /// Called when inline editing ends, so the keyboard can go back to the terminal.
    var onEditingEnded: (() -> Void)?

    private static let savedKey = "trayTopRight"
    private let panelWidth: CGFloat = 360

    init(host: NSRect, label: String, items: [Annotation], cascade: Int) {
        self.host = host
        self.label = label
        self.items = items
        var tr = NSPoint(x: host.maxX - 12, y: host.maxY - 44)
        if let saved = UserDefaults.standard.array(forKey: Self.savedKey) as? [Double], saved.count == 2 {
            let p = NSPoint(x: saved[0], y: saved[1])
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(p) }) { tr = p }
        }
        tr.x -= CGFloat(cascade) * 28
        tr.y -= CGFloat(cascade) * 28
        topRight = tr
        panel = TrayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        render(notify: false)
        panel.orderFrontRegardless()
    }

    func add(_ a: Annotation) {
        items.append(a)
        render()
    }

    func close() { panel.orderOut(nil) }

    func applyVisibility() {
        if tabShown && appShown { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    // MARK: rendering

    private func render(notify: Bool = true) {
        if notify { onChange?(items) }
        discardArmed = false
        renderPanel()
    }

    private func renderPanel() {
        let w = panelWidth
        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 200))
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.background.cgColor
        root.layer?.cornerRadius = 14
        root.layer?.borderWidth = 1
        root.layer?.borderColor = Theme.ginger.cgColor

        let ears = EarsView()
        ears.translatesAutoresizingMaskIntoConstraints = false
        ears.widthAnchor.constraint(equalToConstant: 16).isActive = true
        ears.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let title = makeLabel("Review · \(items.count) comment\(items.count == 1 ? "" : "s")",
                              Theme.mono(13, .bold), Theme.ginger, lines: 1)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        let pane = makeLabel(label, NSFont.systemFont(ofSize: 10.5), Theme.dim, lines: 1)
        pane.toolTip = "This review is sent to “\(label)”"
        let grip = makeLabel("⠿", NSFont.systemFont(ofSize: 13, weight: .bold), Theme.dim, lines: 1)
        grip.setContentCompressionResistancePriority(.required, for: .horizontal)
        let header = DragHandle(views: [ears, title, NSView(), pane, grip])
        header.orientation = .horizontal
        header.spacing = 6
        header.toolTip = "Drag to move"

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        if items.isEmpty {
            list.addArrangedSubview(makeLabel("Select text, press the hotkey, comment.\nComments collect here until you send them.",
                                              Theme.mono(11), Theme.dim, width: w - 28))
        }
        for (i, item) in items.enumerated() {
            let c = card(item, index: i)
            list.addArrangedSubview(c)
            c.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: doc.topAnchor),
            list.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        let discard = makeButton("Discard", Theme.dim, filled: false, #selector(discard(_:)))
        let send = makeButton("Send \(items.count) to Claude Code", Theme.ginger, filled: true, #selector(sendAll))
        send.isEnabled = !items.isEmpty
        send.alphaValue = items.isEmpty ? 0.4 : 1
        let buttons = NSStackView(views: [discard, NSView(), send])
        buttons.orientation = .horizontal
        let caption = makeLabel("Send ends the review. Or ⌘⏎ in the comment box.", NSFont.systemFont(ofSize: 10.5), Theme.dim, lines: 1)
        let footer = NSStackView(views: [buttons, caption])
        footer.orientation = .vertical
        footer.alignment = .trailing
        footer.spacing = 6
        buttons.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true

        let chrome: CGFloat = 14 + 20 + 10 + 10 + 26 + 6 + 14 + 14
        let h = max(170, min(host.height - 80, chrome + list.fittingSize.height + 4))
        root.setFrameSize(NSSize(width: w, height: h))

        let col = NSStackView(views: [header, scroll, footer])
        col.orientation = .vertical
        col.spacing = 10
        col.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        col.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: root.topAnchor),
            col.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            col.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -28),
            scroll.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -28),
            footer.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -28),
        ])
        panel.contentView = root
        placing = true
        panel.setFrame(NSRect(x: topRight.x - w, y: topRight.y - h, width: w, height: h), display: true)
        placing = false
        if let e = editor {
            panel.makeFirstResponder(e)
            let end = (e.stringValue as NSString).length
            e.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
        }
    }

    private func card(_ item: Annotation, index: Int) -> NSView {
        let c = NSView()
        c.wantsLayer = true
        c.layer?.backgroundColor = Theme.card.cgColor
        c.layer?.cornerRadius = 8
        let editing = editingIndex == index
        if editing {
            c.layer?.borderWidth = 1
            c.layer?.borderColor = Theme.ginger.cgColor
        }
        let inner = panelWidth - 28 - 20
        let full = open.contains(index) || editing
        let num = makeLabel("\(index + 1)", Theme.mono(11, .bold), Theme.ginger, lines: 1)
        num.setContentHuggingPriority(.required, for: .horizontal)
        num.setContentCompressionResistancePriority(.required, for: .horizontal)
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.ginger.withAlphaComponent(0.7).cgColor
        bar.widthAnchor.constraint(equalToConstant: 2).isActive = true
        let quote = makeLabel(item.quote.isEmpty ? "(general comment)" : Message.squash(item.quote),
                              Theme.mono(11), Theme.dim, lines: full ? 0 : 1, width: inner - 70)
        quote.setContentHuggingPriority(.init(1), for: .horizontal)
        let edit = icon("✎", "Edit (or double-click the card)", index, #selector(startEdit(_:)))
        let del = icon("×", "Remove this comment", index, #selector(remove(_:)))
        let quoteRow = NSStackView(views: [num, bar, quote, edit, del])
        quoteRow.orientation = .horizontal
        quoteRow.alignment = .top
        quoteRow.spacing = 8
        bar.heightAnchor.constraint(equalTo: quote.heightAnchor).isActive = true

        var rows: [NSView] = [quoteRow]
        if !item.tag.isEmpty {
            rows.append(makeLabel("# " + item.tag, Theme.mono(11, .semibold), Theme.ginger, lines: 1))
        }
        if editing {
            let e = NSTextField(string: item.comment)
            e.font = Theme.mono(12)
            e.textColor = Theme.text
            e.backgroundColor = Theme.field
            e.drawsBackground = true
            e.isBordered = false
            e.focusRingType = .none
            e.usesSingleLineMode = false
            e.cell?.wraps = true
            e.cell?.isScrollable = false
            e.delegate = self
            e.preferredMaxLayoutWidth = inner
            editorHeight = e.heightAnchor.constraint(equalToConstant: 18)
            editorHeight?.isActive = true
            editor = e
            fitEditor()
            rows.append(e)
            rows.append(makeLabel("⏎ save · ⇧⏎ new line · esc cancel", NSFont.systemFont(ofSize: 10.5), Theme.dim, lines: 1))
        } else {
            rows.append(makeLabel(item.comment, Theme.mono(12), Theme.text, lines: full ? 0 : 2, width: inner))
        }

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: c.topAnchor),
            stack.bottomAnchor.constraint(equalTo: c.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: c.trailingAnchor),
        ])
        for r in rows { r.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true }
        if !editing {
            let single = NSClickGestureRecognizer(target: self, action: #selector(toggleCard(_:)))
            let double = NSClickGestureRecognizer(target: self, action: #selector(doubleClickCard(_:)))
            double.numberOfClicksRequired = 2
            single.delegate = self
            c.addGestureRecognizer(single)
            c.addGestureRecognizer(double)
            c.toolTip = full ? "Click to collapse · double-click to edit" : "Click to show in full · double-click to edit"
        }
        c.identifier = NSUserInterfaceItemIdentifier("\(index)")
        return c
    }

    // MARK: helpers

    private func makeLabel(_ s: String, _ font: NSFont, _ color: NSColor, lines: Int = 0, width: CGFloat = 0) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = font
        l.textColor = color
        l.maximumNumberOfLines = lines
        l.lineBreakMode = .byWordWrapping
        l.cell?.truncatesLastVisibleLine = true
        if width > 0 { l.preferredMaxLayoutWidth = width }
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func makeButton(_ title: String, _ color: NSColor, filled: Bool, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 13
        b.layer?.backgroundColor = filled ? color.cgColor : NSColor.clear.cgColor
        b.layer?.borderColor = color.cgColor
        b.layer?.borderWidth = filled ? 0 : 1
        b.attributedTitle = NSAttributedString(string: "  \(title)  ", attributes: [
            .foregroundColor: filled ? NSColor.black : color, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    private func icon(_ glyph: String, _ tip: String, _ index: Int, _ action: Selector) -> NSButton {
        let b = NSButton(title: "", target: self, action: action)
        b.isBordered = false
        b.tag = index
        b.toolTip = tip
        b.attributedTitle = NSAttributedString(string: glyph, attributes: [
            .foregroundColor: Theme.dim, .font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        return b
    }

    private func fitEditor() {
        guard let e = editor else { return }
        let w = panelWidth - 28 - 20
        let need = e.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: 1000)).height
        editorHeight?.constant = max(need, 18) + 17
    }

    // MARK: actions

    func gestureRecognizer(_ g: NSGestureRecognizer, shouldRequireFailureOf other: NSGestureRecognizer) -> Bool {
        (g as? NSClickGestureRecognizer)?.numberOfClicksRequired == 1
            && (other as? NSClickGestureRecognizer)?.numberOfClicksRequired == 2
    }

    func windowDidMove(_ n: Notification) {
        if placing { return }  // only remember moves the user made
        topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        UserDefaults.standard.set([topRight.x, topRight.y], forKey: Self.savedKey)
    }

    private func index(of g: NSGestureRecognizer) -> Int? { Int(g.view?.identifier?.rawValue ?? "") }

    @objc private func toggleCard(_ g: NSClickGestureRecognizer) {
        guard let i = index(of: g) else { return }
        if open.contains(i) { open.remove(i) } else { open.insert(i) }
        renderPanel()
    }

    @objc private func doubleClickCard(_ g: NSClickGestureRecognizer) {
        if let i = index(of: g) { beginEditing(i) }
    }

    @objc private func startEdit(_ sender: NSButton) { beginEditing(sender.tag) }

    private func beginEditing(_ i: Int) {
        editingIndex = i
        panel.editing = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        renderPanel()
    }

    private func endEditing(save keep: Bool) {
        if keep, let i = editingIndex, let e = editor {
            let t = e.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { items[i].comment = t }
        }
        editingIndex = nil
        editor = nil
        editorHeight = nil
        panel.editing = false
        render()
        onEditingEnded?()
    }

    func controlTextDidChange(_ n: Notification) { fitEditor() }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
                fitEditor()
            } else {
                endEditing(save: true)
            }
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { endEditing(save: false); return true }
        return false
    }

    @objc private func remove(_ sender: NSButton) {
        items.remove(at: sender.tag)
        open = Set(open.compactMap { $0 < sender.tag ? $0 : $0 > sender.tag ? $0 - 1 : nil })
        render()
    }

    @objc func sendAll() {
        if editingIndex != nil { endEditing(save: true) }
        onSend?(items)
    }

    // Two clicks to discard, so a whole review is never lost by accident.
    @objc private func discard(_ sender: NSButton) {
        if items.isEmpty || discardArmed { onDiscard?(); return }
        discardArmed = true
        sender.attributedTitle = NSAttributedString(string: "  Click again to discard  ", attributes: [
            .foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        sender.layer?.borderColor = NSColor.systemRed.cgColor
    }
}

final class TrayPanel: NSPanel {
    var editing = false
    override var canBecomeKey: Bool { editing }  // keyboard only while editing a card
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Header row that drags the whole panel.
final class DragHandle: NSStackView {
    override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) }
    override var mouseDownCanMoveWindow: Bool { true }
}
