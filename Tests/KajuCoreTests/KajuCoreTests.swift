// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation
import Testing
@testable import KajuCore

@Suite struct MessageTests {
    @Test func singleQuotesSelectionAndTagsComment() {
        let m = Message.single(Annotation(quote: "line one\n  line two  \n", comment: "do X", tag: "fix"))
        #expect(m == "> line one\n>   line two\n\n[fix] do X")
    }

    @Test func generalCommentHasNoQuote() {
        #expect(Message.single(Annotation(quote: "  \n", comment: "general")) == "general")
    }

    @Test func reviewIsNumbered() {
        let m = Message.review([Annotation(quote: "a", comment: "one"), Annotation(quote: "", comment: "two", tag: "nit")])
        #expect(m == "Review comments (2):\n\n1.\n> a\n\none\n\n2.\n[nit] two")
    }

    @Test func singleLineHasNoControlCharacters() {
        let nasty = "> rm -rf x\r\n\tline\u{1B}[200~two\u{07}\n\n\u{9B}end\u{7F}"
        let flat = Message.singleLine(nasty)
        let controls = flat.unicodeScalars.filter { $0.value < 0x20 || $0.value == 0x7F || (0x80...0x9F).contains($0.value) }
        #expect(controls.isEmpty)
        #expect(!flat.contains("\n") && !flat.contains("\r"))
        #expect(flat.contains("⏎"))
    }

    @Test func singleLineOfWholeReviewIsSafe() {
        let flat = Message.singleLine(Message.review([Annotation(quote: "x\ny", comment: "z")]))
        #expect(flat.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F })
    }

    @Test func decodesPrototypeItemsWithoutTag() throws {
        let c = try JSONDecoder().decode(Annotation.self, from: Data(#"{"quote":"q","comment":"c"}"#.utf8))
        #expect(c == Annotation(quote: "q", comment: "c", tag: ""))
    }
}

@Suite struct LivenessTests {
    @Test func acceptsNativeBinaryAndNpmInstall() {
        #expect(Liveness.isClaude(argv: ["/Users/me/.local/bin/claude"]))
        #expect(Liveness.isClaude(argv: ["claude", "--resume"]))
        #expect(Liveness.isClaude(argv: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"]))
    }

    @Test func refusesShellsAndLookalikes() {
        #expect(!Liveness.isClaude(argv: ["-zsh"]))
        #expect(!Liveness.isClaude(argv: ["/bin/bash"]))
        #expect(!Liveness.isClaude(argv: ["node", "/Users/me/claude-notes/server.js"]))
        #expect(!Liveness.isClaude(argv: ["python3", "claude"]))
        #expect(!Liveness.isClaude(argv: []))
    }

    @Test func onlyTheForegroundGroupLeaderCounts() {
        // claude in the background (pid != tpgid), shell in front: refuse.
        let shellInFront = """
          501  777 -zsh
          600  777 claude
          777  777 vim notes.txt
        """
        #expect(!Liveness.claudeInForeground(psOutput: shellInFront))
        let claudeInFront = """
          501  600 -zsh
          600  600 /Users/me/.local/bin/claude
          650  600 python3 helper.py
        """
        #expect(Liveness.claudeInForeground(psOutput: claudeInFront))
    }

    @Test func usesPsThroughTheInjectedShell() {
        var called: [String] = []
        let fake = Shell { path, args, _ in
            called = [path] + args
            return (0, "  10 10 claude\n")
        }
        #expect(Liveness.claudeInForeground(tty: "/dev/ttys004", shell: fake))
        #expect(called == ["/bin/ps", "-t", "ttys004", "-o", "pid=,tpgid=,args="])
        let failing = Shell { _, _, _ in (1, "") }
        #expect(!Liveness.claudeInForeground(tty: "/dev/ttys004", shell: failing))
    }
}

@Suite struct ClipboardPolicyTests {
    let terminals: Set<String> = ["com.mitchellh.ghostty"]
    let now = Date(timeIntervalSince1970: 1000)

    @Test func visibleCheckNeedsTheTextOnScreen() {
        #expect(ClipboardPolicy.acceptVisible(clipboard: "hello   world", visibleText: "x hello world y", concealed: false))
        #expect(!ClipboardPolicy.acceptVisible(clipboard: "secret", visibleText: "nothing here", concealed: false))
        #expect(!ClipboardPolicy.acceptVisible(clipboard: "hello", visibleText: "hello", concealed: true))
    }

    @Test func genericAcceptsRecentTerminalChange() {
        let c = ClipboardPolicy.Change(count: 5, time: now.addingTimeInterval(-10), frontmostBundle: "com.mitchellh.ghostty", concealed: false, ownWrite: false)
        #expect(ClipboardPolicy.acceptGeneric(last: c, currentCount: 5, now: now, window: 30, terminalBundles: terminals))
    }

    @Test func genericRejectsOldOwnConcealedOrOtherApp() {
        func change(_ t: TimeInterval = -10, app: String = "com.mitchellh.ghostty", concealed: Bool = false, own: Bool = false) -> ClipboardPolicy.Change {
            .init(count: 5, time: now.addingTimeInterval(t), frontmostBundle: app, concealed: concealed, ownWrite: own)
        }
        #expect(!ClipboardPolicy.acceptGeneric(last: change(-60), currentCount: 5, now: now, window: 30, terminalBundles: terminals))
        #expect(!ClipboardPolicy.acceptGeneric(last: change(own: true), currentCount: 5, now: now, window: 30, terminalBundles: terminals))
        #expect(!ClipboardPolicy.acceptGeneric(last: change(concealed: true), currentCount: 5, now: now, window: 30, terminalBundles: terminals))
        #expect(!ClipboardPolicy.acceptGeneric(last: change(app: "com.1password.1password"), currentCount: 5, now: now, window: 30, terminalBundles: terminals))
        #expect(!ClipboardPolicy.acceptGeneric(last: change(), currentCount: 6, now: now, window: 30, terminalBundles: terminals))
        #expect(!ClipboardPolicy.acceptGeneric(last: nil, currentCount: 5, now: now, window: 30, terminalBundles: terminals))
    }
}

@Suite struct ConfigTests {
    @Test func defaultsAndPartialFiles() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+shift+;"}"#.utf8))
        #expect(c.hotkey == "cmd+shift+;")
        #expect(c.tags == ["fix", "question", "nit"])
        #expect(c.clipboardWindowSeconds == 30)
    }

    @Test func hotkeyParsing() {
        let h = Hotkey("ctrl+opt+k")
        #expect(h?.key == "k" && h?.modifiers == [.ctrl, .opt])
        #expect(h?.display == "⌃⌥K")
        #expect(h?.keyCode == 40)
        #expect(Hotkey("k") == nil)           // needs a modifier
        #expect(Hotkey("ctrl+kk") == nil)     // one key only
        #expect(Hotkey("ctrl+k+j") == nil)
    }

    @Test func writesDefaultsOnFirstLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("config.json")
        #expect(Config.load(from: url) == Config())
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite struct TmuxTests {
    @Test func parsesPaneLines() {
        let p = Tmux.parsePane("%3\t/dev/ttys009\twork:1.0\t1\t✳ Claude Code")
        #expect(p == Tmux.Pane(id: "%3", tty: "/dev/ttys009", address: "work:1.0", windowActive: true, title: "✳ Claude Code"))
        #expect(Tmux.parsePane("garbage") == nil)
    }

    @Test func findsClientOnHostTTYOnly() {
        let fake = Shell { _, args, _ in
            args.contains("list-clients") ? (0, "/dev/ttys004\n/dev/ttys008\n") : (1, "")
        }
        let t = Tmux(path: "/fake/tmux", shell: fake)
        #expect(t.client(onTTY: "/dev/ttys008") == "/dev/ttys008")
        #expect(t.client(onTTY: "/dev/ttys001") == nil)
    }

    @Test func deliversWithBracketedPasteThenEnter() {
        var calls: [[String]] = []
        var input: String?
        let fake = Shell { _, args, inp in
            calls.append(args)
            if inp != nil { input = inp }
            return (0, "")
        }
        let t = Tmux(path: "/fake/tmux", socket: "/tmp/s", shell: fake)
        #expect(t.deliver("> q\n\nc", paneID: "%3", submit: true))
        #expect(input == "> q\n\nc")
        #expect(calls[0] == ["-S", "/tmp/s", "load-buffer", "-b", "kaju", "-"])
        #expect(calls[1] == ["-S", "/tmp/s", "paste-buffer", "-p", "-d", "-b", "kaju", "-t", "%3"])
        #expect(calls[2] == ["-S", "/tmp/s", "send-keys", "-t", "%3", "Enter"])
    }

    @Test func locatePrefersConfiguredPath() {
        #expect(Tmux.locate(configured: "/x/tmux", fileExists: { $0 == "/x/tmux" || $0 == "/opt/homebrew/bin/tmux" }) == "/x/tmux")
        #expect(Tmux.locate(configured: nil, fileExists: { $0 == "/usr/local/bin/tmux" }) == "/usr/local/bin/tmux")
        #expect(Tmux.locate(configured: nil, fileExists: { _ in false }) == nil)
    }
}

@Suite struct ReviewStoreTests {
    func tempStore() -> ReviewStore {
        ReviewStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func saveLoadDelete() throws {
        let s = tempStore()
        let r = ReviewFile(key: "tmux:work:1.0", label: "work", items: [Annotation(quote: "q", comment: "c", tag: "fix")])
        try s.save(r)
        #expect(s.load(key: "tmux:work:1.0") == r)
        #expect(s.all() == [r])
        s.delete(key: "tmux:work:1.0")
        #expect(s.load(key: "tmux:work:1.0") == nil)
    }

    @Test func importsPrototypeReviews() throws {
        let s = tempStore()
        let old = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data(#"[{"quote":"q","comment":"c","tag":"nit"}]"#.utf8).write(to: old.appendingPathComponent("ABC-123.json"))
        #expect(s.importPrototype(from: old) == 1)
        #expect(s.load(key: "iterm2:ABC-123")?.items == [Annotation(quote: "q", comment: "c", tag: "nit")])
        #expect((try? FileManager.default.contentsOfDirectory(atPath: old.path))?.isEmpty == true)
    }
}

@Suite struct ReviewFixTests {
    @Test func messageStripsEscapesButKeepsLines() {
        let m = Message.single(Annotation(quote: "a\u{1B}[201~b\r\nc", comment: "x\u{07}y\tz"))
        #expect(!m.unicodeScalars.contains { $0.value == 0x1B || $0.value == 0x07 || $0 == "\r" })
        #expect(m == "> a[201~b\n> c\n\nxy\tz")
    }

    @Test func ownWriteIsNeverQuoted() {
        let own = ClipboardPolicy.Change(count: 9, time: Date(), frontmostBundle: nil, concealed: false, ownWrite: true)
        #expect(ClipboardPolicy.isOwnWrite(last: own, currentCount: 9))
        #expect(!ClipboardPolicy.isOwnWrite(last: own, currentCount: 10))  // changed since
    }

    @Test func shellTimesOut() {
        let start = Date()
        #expect(Shell.real(timeout: 0.5).run("/bin/sleep", ["5"]) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func moreHotkeyKeys() {
        #expect(Hotkey("ctrl+opt+[")?.keyCode == 33)
        #expect(Hotkey("cmd+shift+-")?.keyCode == 27)
    }
}
