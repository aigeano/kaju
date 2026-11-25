// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit
import KajuCore

/// iTerm2, through a Python helper that uses iTerm2's Python API. Full tier:
/// exact session, placement at the selection, per-tab visibility, and
/// delivery straight into the session after the liveness check.
final class ITerm2Adapter: TerminalAdapter {
    let name = "iTerm2"
    let bundleIDs: Set<String> = ["com.googlecode.iterm2"]
    static let bundleID = "com.googlecode.iterm2"

    /// Called on the main thread when the user picks "Comment with kaju" in iTerm2.
    var onMenu: ((String) -> Void)?
    /// Last helper problem, shown in the menu bar.
    private(set) var problem: String?

    private let python: String?
    private let script: String
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: (DispatchSemaphore, [String: Any]?)] = [:]
    private let lock = NSLock()
    private(set) var ready = false

    init(python: String?, script: String) {
        self.python = python
        self.script = script
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if Self.isITerm(n) { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.start() } }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if Self.isITerm(n) { self?.stop() }
        }
        if Self.iTermRunning { start() }
    }

    static func isITerm(_ n: Notification) -> Bool {
        (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleID
    }

    static var iTermRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var available: Bool { ready && process?.isRunning == true }

    // MARK: helper process

    func start() {
        guard process?.isRunning != true else { return }
        guard let python, FileManager.default.isExecutableFile(atPath: python) else {
            problem = "iTerm2 support needs kaju's Python environment (run the installer again)."
            Log.info(problem!)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-I", script]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.received(d)
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.ready = false
                self.failAll()
                Log.info("iTerm2 helper exited")
                // Restart while iTerm2 is still running (for example after an iTerm2 API hiccup).
                if Self.iTermRunning {
                    self.problem = "The iTerm2 helper stopped. Is the Python API enabled in iTerm2 (Settings › General › Magic)?"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.start() }
                }
            }
        }
        do { try p.run() } catch { problem = "Could not start the iTerm2 helper: \(error.localizedDescription)"; Log.info(problem!); return }
        Log.info("iTerm2 helper started (\(python))")
        process = p
        stdin = inPipe.fileHandleForWriting
    }

    func stop() {
        ready = false
        process?.terminate()
        process = nil
        failAll()
    }

    private func failAll() {
        lock.lock(); let waiting = pending; pending.removeAll(); lock.unlock()
        for (_, (sem, _)) in waiting { sem.signal() }
    }

    private func received(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let event = msg["event"] as? String {
                DispatchQueue.main.async {
                    if event == "ready" { self.ready = true; self.problem = nil; Log.info("iTerm2 helper ready") }
                    if event == "menu", let s = msg["session"] as? String { self.onMenu?(s) }
                }
            } else if let id = msg["id"] as? Int {
                lock.lock()
                if let (sem, _) = pending[id] { pending[id] = (sem, msg); sem.signal() }
                lock.unlock()
            }
        }
    }

    /// Send a request and wait for the reply. Off the main thread only.
    func request(_ op: String, _ params: [String: Any] = [:], timeout: TimeInterval = 3) -> [String: Any]? {
        guard available, let stdin else { return nil }
        let sem = DispatchSemaphore(value: 0)
        lock.lock()
        let id = nextID; nextID += 1
        pending[id] = (sem, nil)
        lock.unlock()
        var msg = params
        msg["id"] = id
        msg["op"] = op
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return nil }
        stdin.write(data + Data([0x0A]))
        _ = sem.wait(timeout: .now() + timeout)
        lock.lock(); let reply = pending.removeValue(forKey: id)?.1; lock.unlock()
        guard let reply, reply["ok"] as? Bool == true else { return nil }
        return reply
    }

    // MARK: adapter

    func target(app: NSRunningApplication) -> Target? {
        guard let r = request("front"), let sid = r["session"] as? String else { return nil }
        return target(session: sid, tty: r["tty"] as? String, name: r["name"] as? String, pid: app.processIdentifier)
    }

    /// Target for a session named by the right-click menu.
    func target(session sid: String) -> Target? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first,
              let r = request("info", ["session": sid]) else { return nil }
        return target(session: sid, tty: r["tty"] as? String, name: r["name"] as? String, pid: app.processIdentifier)
    }

    private func target(session sid: String, tty: String?, name: String?, pid: pid_t) -> Target {
        Target(key: "iterm2:\(sid)", label: (name?.isEmpty == false ? name! : "iTerm2"), bundleID: Self.bundleID,
               pid: pid, tty: tty, windowID: nil, ref: ["session": sid])
    }

    func selectionAnchor(_ t: Target, clipboard: String) -> NSPoint? {
        guard let sid = t.ref["session"], let r = request("screen", ["session": sid]),
              let lines = r["lines"] as? [String], let area = r["area"] as? [Double], area.count == 4,
              let cols = r["cols"] as? Double, let rows = r["rows"] as? Double, cols > 0, rows > 0 else { return nil }
        // Find where the clipboard's last line ends on screen (short keys survive line wrapping).
        let last = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").last?.trimmingCharacters(in: .whitespaces) ?? ""
        for key in [String(last.suffix(12)), String(last.prefix(12))] where !key.isEmpty {
            for row in stride(from: lines.count - 1, through: 0, by: -1) {
                if let range = lines[row].range(of: key) {
                    let col = lines[row].distance(from: lines[row].startIndex, to: range.upperBound)
                    let cellW = area[2] / cols, cellH = area[3] / rows
                    return NSPoint(x: area[0] + Double(col) * cellW, y: area[1] + area[3] - Double(row) * cellH)
                }
            }
        }
        return nil
    }

    func visibleText(_ t: Target) -> String? {
        guard let sid = t.ref["session"], let r = request("screen", ["session": sid]),
              let lines = r["lines"] as? [String] else { return nil }
        return lines.joined(separator: "\n")
    }

    func windowFrame(_ t: Target) -> NSRect? {
        guard let sid = t.ref["session"], let r = request("frame", ["session": sid]),
              let f = r["frame"] as? [Double], f.count == 4 else { return nil }
        return NSRect(x: f[0], y: f[1], width: f[2], height: f[3])
    }

    func isTabSelected(_ t: Target) -> Bool {
        guard let sid = t.ref["session"] else { return false }
        return request("selected", ["session": sid], timeout: 1)?["selected"] as? Bool ?? false
    }

    func isClaudeRunning(_ t: Target) -> Bool? {
        guard let tty = t.tty else { return false }
        return Liveness.claudeInForeground(tty: tty)
    }

    func activate(_ t: Target) {
        if let sid = t.ref["session"] { _ = request("activate", ["session": sid]) }
        System.activate(pid: t.pid)
    }

    func deliver(_ text: String, to t: Target, mode: DeliveryMode) -> DeliveryResult {
        guard let sid = t.ref["session"] else { return .failed("iTerm2 session unknown") }
        guard request("send", ["session": sid, "text": text, "submit": mode == .submit], timeout: 5) != nil else {
            return .failed("iTerm2 did not accept the text. Is the Python API enabled (Settings › General › Magic)?")
        }
        return mode == .submit ? .sent : .pasted
    }
}
