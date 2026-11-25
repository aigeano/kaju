// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import KajuCore

/// One pane kaju is working with: its open comment input and/or review panel.
final class PaneSession {
    var target: Target
    var adapter: TerminalAdapter
    var input: CommentInput?
    var panel: ReviewPanel?
    /// True while the review panel is being opened (its frame is fetched off the main thread).
    var panelPending = false

    init(target: Target, adapter: TerminalAdapter) {
        self.target = target
        self.adapter = adapter
    }
    var isEmpty: Bool { input == nil && panel == nil && !panelPending }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = Config.load()
    private let store = ReviewStore.standard
    private let clipboard = ClipboardMonitor()
    private var hotkey: HotkeyManager!
    private var hotkeyOK = false
    private var statusItem: NSStatusItem!
    private var iterm: ITerm2Adapter?
    private var terminalApp: TerminalAppAdapter!
    private var generic: GenericAdapter!
    private var tmux: Tmux?
    private var sessions: [String: PaneSession] = [:]
    private var visibilityTimer: Timer?
    private let work = DispatchQueue(label: "kaju.work")

    func applicationDidFinishLaunching(_ n: Notification) {
        terminalApp = TerminalAppAdapter(clipboard: clipboard)
        generic = GenericAdapter(clipboard: clipboard)
        if let path = Tmux.locate(configured: config.tmuxPath) {
            tmux = Tmux(path: path, socket: config.tmuxSocket)
        }
        if let script = Self.resource("kaju_iterm2_helper.py") {
            let it = ITerm2Adapter(python: Self.pythonPath(), script: script)
            it.onMenu = { [weak self] sid in self?.trigger(iTermSession: sid) }
            it.onReady = { [weak self] in self?.restoreReviews(onlyITerm: true) }
            iterm = it
        }
        hotkey = HotkeyManager { [weak self] in self?.trigger() }
        registerHotkey()
        Log.info("kaju started; hotkey \(hotkeyDisplay) \(hotkeyOK ? "registered" : "UNAVAILABLE"); tmux \(tmux?.path ?? "not found")")
        setUpStatusItem()
        importPrototypeReviews()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateVisibility() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Reopen saved reviews; iTerm2 ones are restored again when its helper is ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.restoreReviews(onlyITerm: false) }
    }

    // MARK: resources

    static func resource(_ name: String) -> String? {
        if let dir = ProcessInfo.processInfo.environment["KAJU_RESOURCES"] {
            return (dir as NSString).appendingPathComponent(name)
        }
        return Bundle.main.path(forResource: (name as NSString).deletingPathExtension,
                                ofType: (name as NSString).pathExtension)
    }

    /// Python with the `iterm2` package: $KAJU_PYTHON, the path written at build
    /// time (Resources/python-path), or kaju's own venv.
    static func pythonPath() -> String? {
        if let p = ProcessInfo.processInfo.environment["KAJU_PYTHON"] { return p }
        if let f = resource("python-path"), let p = try? String(contentsOfFile: f, encoding: .utf8) {
            return p.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let venv = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kaju/venv/bin/python").path
        return FileManager.default.isExecutableFile(atPath: venv) ? venv : nil
    }

    // MARK: hotkey and menu

    private func registerHotkey() {
        if let h = Hotkey(config.hotkey) {
            hotkeyOK = hotkey.register(h)
        } else {
            hotkeyOK = false
        }
    }

    private var hotkeyDisplay: String { Hotkey(config.hotkey)?.display ?? config.hotkey }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Theme.earsImage(size: NSSize(width: 18, height: 18), template: true)
        statusItem.button?.toolTip = "kaju"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let m = NSMenu()
        m.delegate = self
        fill(m)
        statusItem.menu = m
    }

    /// Menu contents; rebuilt each time the menu opens so warnings are current.
    private func fill(_ m: NSMenu) {
        m.removeAllItems()
        let comment = NSMenuItem(title: "Comment on selection (\(hotkeyDisplay))", action: #selector(menuComment), keyEquivalent: "")
        comment.target = self
        m.addItem(comment)
        for w in warnings() {
            let item = NSMenuItem(title: "⚠︎ " + w, action: nil, keyEquivalent: "")
            item.isEnabled = false
            m.addItem(item)
        }
        if oldScriptRunning() {
            m.addItem(item("Stop the old claude-annotate script", #selector(stopOldScript)))
        }
        m.addItem(.separator())
        m.addItem(item("Open Accessibility settings…", #selector(openAccessibility)))
        m.addItem(item("Reset permissions (after an upgrade)", #selector(resetPermissions)))
        m.addItem(item("Open config file", #selector(openConfig)))
        m.addItem(item("Reload config", #selector(reloadConfig)))
        m.addItem(.separator())
        m.addItem(item("About kaju", #selector(about)))
        m.addItem(NSMenuItem(title: "Quit kaju", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func warnings() -> [String] {
        var w: [String] = []
        if !hotkeyOK { w.append("Hotkey \(hotkeyDisplay) is unavailable (in use, or invalid in config)") }
        if let p = iterm?.problem, ITerm2Adapter.iTermRunning { w.append(p) }
        return w
    }

    private func oldScriptRunning() -> Bool {
        Shell.system.run("/usr/bin/pgrep", ["-f", "claude_comment.py"]) != nil
    }

    @objc private func menuComment() {
        // The menu took focus from the terminal; give it back, then trigger.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.trigger() }
    }

    @objc private func stopOldScript() {
        _ = Shell.system.run("/usr/bin/pkill", ["-f", "claude_comment.py"])
        alert("The old script was stopped.",
              "Also remove claude-annotate from plugins=(...) in ~/.zshrc and the old iTerm2 key binding, so it does not start again.")
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func resetPermissions() {
        let id = Bundle.main.bundleIdentifier ?? "io.github.aigeano.kaju"
        let a = Shell.system.run("/usr/bin/tccutil", ["reset", "Accessibility", id]) != nil
        let b = Shell.system.run("/usr/bin/tccutil", ["reset", "AppleEvents", id]) != nil
        alert(a && b ? "Permissions reset" : "Could not reset every permission",
              "macOS will ask again the next time kaju needs Accessibility or Automation. After an upgrade, the old entries no longer match the new build, so this reset is needed once.")
    }

    @objc private func openConfig() {
        _ = Config.load()
        NSWorkspace.shared.open(Config.standardURL)
    }

    @objc private func reloadConfig() {
        config = Config.load()
        registerHotkey()
        if let path = Tmux.locate(configured: config.tmuxPath) { tmux = Tmux(path: path, socket: config.tmuxSocket) }
        rebuildMenu()
    }

    @objc private func about() {
        alert("kaju", """
        Annotate, comment and collaborate with Claude Code.

        Named after a ginger cat who appears to run on a single brain cell but is exceptionally good at one thing: eating. kaju is similar: it does not do much, but it is very good at commenting on Claude Code output.

        https://github.com/aigeano/kaju
        """)
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.icon = NSApp.applicationIconImage
        a.runModal()
    }

    // MARK: trigger

    /// Hotkey or "Comment with kaju" in iTerm2: open the input for the front pane.
    func trigger(iTermSession: String? = nil) {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // kaju itself in front means its input already has the keyboard. An open input
        // that lost focus to the terminal is reached below (session exists → focus(quote:)).
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        let bundle = front.bundleIdentifier ?? ""
        work.async { [self] in
            guard let (adapter, target) = resolveTarget(app: front, bundle: bundle, iTermSession: iTermSession) else {
                DispatchQueue.main.async {
                    if !self.generic.bundleIDs.contains(bundle) {
                        self.alert("kaju works in terminal apps", "Select some Claude Code output in a terminal, then press \(self.hotkeyDisplay).")
                    }
                }
                return
            }
            let selection = captureSelection(adapter: adapter, target: target)
            Log.info("comment input for \(adapter.name) \(target.key); selection \(selection.isEmpty ? "none" : "\(selection.count) chars")")
            let anchor = selection.isEmpty ? nil : adapter.selectionAnchor(target, clipboard: selection)
            DispatchQueue.main.async { self.openInput(adapter: adapter, target: target, quote: selection, anchor: anchor) }
        }
    }

    /// The adapter for the front app, wrapped by tmux when a tmux client is attached on its tty.
    private func resolveTarget(app: NSRunningApplication, bundle: String, iTermSession: String?) -> (TerminalAdapter, Target)? {
        var host: (TerminalAdapter, Target)?
        if bundle == ITerm2Adapter.bundleID, let it = iterm, it.available {
            if let sid = iTermSession, let t = it.target(session: sid) { host = (it, t) }
            else if let t = it.target(app: app) { host = (it, t) }
        } else if terminalApp.bundleIDs.contains(bundle) {
            guard let t = terminalApp.target(app: app) else {
                // Never fall back silently to paste-only for Terminal: say what is missing.
                let why = terminalApp.problem ?? "Terminal did not answer."
                Log.info("Terminal.app target unavailable: \(why)")
                DispatchQueue.main.async { self.alert("kaju cannot reach Terminal", why) }
                return nil
            }
            host = (terminalApp, t)
        }
        if let (a, t) = host {
            if let wrapped = TmuxAdapter.wrap(a, t, tmux: tmux) { return wrapped }
            return host
        }
        // Basic tier for any other known terminal (and as a fallback for iTerm2 without its helper).
        guard generic.bundleIDs.contains(bundle), let t = generic.target(app: app) else { return nil }
        return (generic, t)
    }

    /// The selection, read from the clipboard (Claude Code copies on select),
    /// accepted only if it is fresh; empty means a general comment.
    private func captureSelection(adapter: TerminalAdapter, target: Target) -> String {
        let (text, concealed, count, last) = DispatchQueue.main.sync {
            (clipboard.text ?? "", clipboard.isConcealed, clipboard.changeCount, clipboard.lastChange)
        }
        if text.isEmpty || concealed { return "" }
        // A comment kaju itself copied (after a refusal) is never quoted back.
        if ClipboardPolicy.isOwnWrite(last: last, currentCount: count) { return "" }
        if let visible = adapter.visibleText(target) {
            return ClipboardPolicy.acceptVisible(clipboard: text, visibleText: visible, concealed: concealed) ? text : ""
        }
        let ok = ClipboardPolicy.acceptGeneric(last: last, currentCount: count, now: Date(),
                                               window: config.clipboardWindowSeconds, terminalBundles: generic.bundleIDs)
        return ok ? text : ""
    }

    // MARK: input and reviews

    private func session(for adapter: TerminalAdapter, _ target: Target) -> PaneSession {
        if let s = sessions[target.key] {
            s.target = target
            s.adapter = adapter  // e.g. a tmux pane reached from another host tab
            return s
        }
        let s = PaneSession(target: target, adapter: adapter)
        sessions[target.key] = s
        // A review saved earlier for this pane (for example before a restart) comes back here.
        if let saved = store.load(key: target.key), !saved.items.isEmpty { ensurePanel(s, items: saved.items) {} }
        return s
    }

    private func openInput(adapter: TerminalAdapter, target: Target, quote: String, anchor: NSPoint?) {
        let s = session(for: adapter, target)
        if let input = s.input {  // already open here: give it the new quote
            input.focus(quote: quote)
            return
        }
        let input = CommentInput(anchor: anchor, quote: quote, pending: s.panel?.items.count ?? 0, tags: config.tags) { [weak self, weak s] result in
            guard let self, let s else { return }
            s.input = nil
            self.finishInput(s, result)
        }
        s.input = input
        input.show()
    }

    private func finishInput(_ s: PaneSession, _ result: CommentInput.Result?) {
        defer { cleanUp(s) }
        guard let r = result else { returnFocus(s); return }  // Esc
        let a = Annotation(quote: r.quote.trimmingCharacters(in: .whitespacesAndNewlines), comment: r.comment, tag: r.tag)
        switch r.action {
        case .send:
            deliver(Message.single(a), to: s, keepOnFailure: nil)
        case .add:
            ensurePanel(s, items: []) { [weak self, weak s] in
                guard let self, let s else { return }
                s.panel?.add(a)
                self.returnFocus(s)
            }
        case .addAndSend:
            if s.panel == nil {  // no review yet: behaves like a plain send
                deliver(Message.single(a), to: s, keepOnFailure: nil)
            } else {
                if !a.comment.isEmpty { s.panel?.add(a) }
                sendReview(s)
            }
        }
    }

    /// Open the review panel if needed (the window frame is fetched off the main
    /// thread, since it can take an AppleScript or helper round trip), then run `then`.
    private func ensurePanel(_ s: PaneSession, items: [Annotation], then: @escaping () -> Void) {
        if s.panel != nil { then(); return }
        s.panelPending = true  // keeps the session registered until the panel exists
        let (a, t) = (s.adapter, s.target)
        work.async { [weak self] in
            let frame = a.windowFrame(t)
            DispatchQueue.main.async {
                guard let self else { return }
                s.panelPending = false
                if s.panel == nil { self.openPanel(s, items: items, host: frame) }
                then()
            }
        }
    }

    private func openPanel(_ s: PaneSession, items captured: [Annotation], host frame: NSRect?) {
        // The saved file is the source of truth: it may have gained comments (a merged
        // restore) between the request to open the panel and now.
        let items = store.load(key: s.target.key)?.items ?? captured
        let host = frame ?? NSScreen.main?.visibleFrame ?? .zero
        let cascade = sessions.values.filter { $0.panel != nil }.count
        let p = ReviewPanel(host: host, label: s.target.label, items: items, cascade: cascade)
        p.onChange = { [weak self, weak s] items in
            guard let self, let s else { return }
            try? self.store.save(ReviewFile(key: s.target.key, label: s.target.label, items: items))
            s.input?.setPending(items.count)
        }
        p.onSend = { [weak self, weak s] _ in if let self, let s { self.sendReview(s) } }
        p.onDiscard = { [weak self, weak s] in
            guard let self, let s else { return }
            self.store.delete(key: s.target.key)
            s.panel?.close()
            s.panel = nil
            s.input?.setPending(0)
            self.cleanUp(s)
        }
        p.onEditingEnded = { [weak self, weak s] in if let self, let s { self.returnFocus(s) } }
        s.panel = p
        try? store.save(ReviewFile(key: s.target.key, label: s.target.label, items: items))
        s.input?.setPending(items.count)
    }

    private func sendReview(_ s: PaneSession) {
        guard let p = s.panel, !p.items.isEmpty, !p.sending else { return }  // never twice
        let sentCount = p.items.count
        p.setSending(true)
        deliver(Message.review(p.items), to: s) { [weak self, weak s] ok in
            guard let self, let s, let p = s.panel else { return }
            p.setSending(false)
            guard ok else { return }  // on failure the review stays open
            p.removeSent(sentCount)   // comments added while sending stay in the panel
            if p.items.isEmpty {
                self.store.delete(key: s.target.key)
                p.close()
                s.panel = nil
                s.input?.setPending(0)
                self.cleanUp(s)
            }
        }
    }

    private func cleanUp(_ s: PaneSession) {
        if s.isEmpty { sessions[s.target.key] = nil }
    }

    private func returnFocus(_ s: PaneSession) {
        let (a, t) = (s.adapter, s.target)
        work.async { a.activate(t) }
    }

    // MARK: delivery

    /// Deliver text to a pane, with the safety rules: submit only when Claude
    /// Code is confirmed in the foreground, paste only when the adapter cannot
    /// tell, and type nothing when it is known not to be running.
    private func deliver(_ text: String, to s: PaneSession, keepOnFailure done: ((Bool) -> Void)?) {
        let (a, t) = (s.adapter, s.target)
        work.async { [self] in
            let live = a.isClaudeRunning(t)
            let result: DeliveryResult
            if live == false {
                result = .refused("Claude Code is not running in “\(t.label)”, so nothing was typed.")
            } else {
                result = a.deliver(text, to: t, mode: live == true ? .submit : .pasteOnly)
            }
            Log.info("deliver to \(a.name) \(t.key): liveness \(live.map { String($0) } ?? "unknown") -> \(result.kind)")
            if case .sent = result { a.activate(t) }  // keyboard back to the terminal
            DispatchQueue.main.async {
                switch result {
                case .sent, .pasted:
                    done?(true)
                case .refused(let why), .failed(let why):
                    let isReview = done != nil
                    if !isReview { self.clipboard.writeOwn(text, hidden: false) }
                    self.alert("Not sent", why + (isReview ? " Your review is kept in its panel." : " Your comment was copied to the clipboard."))
                    done?(false)
                    self.returnFocus(s)
                }
            }
        }
    }

    // MARK: visibility

    @objc private func appActivated(_ n: Notification) { updateVisibility() }

    /// Show each input and panel only while its terminal app is in front and its tab is selected.
    private var visibilityBusy = false

    private func updateVisibility() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let me = ProcessInfo.processInfo.processIdentifier
        let group = DispatchGroup()
        for s in sessions.values {
            let appShown = front == s.target.pid || front == me
            s.input?.appShown = appShown
            s.panel?.appShown = appShown
            if !appShown || front == me {
                s.input?.applyVisibility()
                s.panel?.applyVisibility()
                continue
            }
            // Skip the tab check while the previous one is still running, so slow
            // answers (a busy helper, AppleScript) never pile up ahead of hotkeys.
            if visibilityBusy { continue }
            let (a, t) = (s.adapter, s.target)
            group.enter()
            work.async {
                let selected = a.isTabSelected(t)
                DispatchQueue.main.async {
                    s.input?.tabShown = selected
                    s.panel?.tabShown = selected
                    s.input?.applyVisibility()
                    s.panel?.applyVisibility()
                    group.leave()
                }
            }
        }
        if !visibilityBusy {
            visibilityBusy = true
            group.notify(queue: .main) { [weak self] in self?.visibilityBusy = false }
        }
    }

    // MARK: restore

    private func importPrototypeReviews() {
        let old = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".oh-my-zsh/custom/plugins/claude-annotate/reviews")
        _ = store.importPrototype(from: old)
    }

    /// Reopen saved reviews (plan: review keys and restore rules).
    /// - iTerm2: the same session if it still exists, else the current session.
    /// - Terminal.app: the same tab (tty in the same window) if Claude Code runs
    ///   there, else the front tab.
    /// - Generic: the front window of the same app.
    /// - tmux: when kaju is next used in that pane.
    /// A review that moves to another pane is saved under its new key.
    private func restoreReviews(onlyITerm: Bool) {
        let saved = store.all().filter { !$0.items.isEmpty && sessions[$0.key] == nil }
        work.async { [self] in
            for r in saved {
                if onlyITerm && !r.key.hasPrefix("iterm2:") { continue }
                guard let (a, found) = resolveSaved(r) else { continue }
                DispatchQueue.main.async {
                    var t = found
                    if t.key != r.key {
                        // Moved to another pane: say so in the panel, and never overwrite a
                        // review already there; merge into it instead.
                        t.label += " · review restored here"
                        self.store.delete(key: r.key)
                        if let open = self.sessions[t.key], let panel = open.panel {
                            r.items.forEach(panel.add)
                            return
                        }
                        let existing = self.store.load(key: t.key)?.items ?? []
                        try? self.store.save(ReviewFile(key: t.key, label: t.label, items: existing + r.items))
                    }
                    if self.sessions[t.key] == nil { _ = self.session(for: a, t) }
                }
            }
        }
    }

    private func resolveSaved(_ r: ReviewFile) -> (TerminalAdapter, Target)? {
        let parts = r.key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let rest = parts[1]
        switch parts[0] {
        case "iterm2":
            guard let it = iterm, it.available,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: ITerm2Adapter.bundleID).first else { return nil }
            if let t = it.target(session: rest) { return (it, t) }
            return it.target(app: app).map { (it, $0) }
        case "terminal":
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first else { return nil }
            let f = rest.split(separator: ":").map(String.init)  // tty, window id
            if f.count == 2, let wid = UInt32(f[1]), terminalApp.tabExists(tty: f[0], windowID: wid),
               Liveness.claudeInForeground(tty: f[0]) {
                return (terminalApp, Target(key: r.key, label: r.label, bundleID: "com.apple.Terminal",
                                            pid: app.processIdentifier, tty: f[0], windowID: wid))
            }
            return terminalApp.target(app: app).map { (terminalApp, $0) }
        case "generic":
            let bundle = String(rest.split(separator: ":").first ?? "")
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return nil }
            return generic.target(app: app).map { (generic, $0) }
        default:
            return nil  // tmux: restored when the pane is next used
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }
}
