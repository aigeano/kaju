// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// kaju's settings, kept in `~/Library/Application Support/kaju/config.json`.
/// Missing keys fall back to the defaults below; the file is created on first run.
public struct Config: Codable, Equatable {
    /// Global hotkey, e.g. "ctrl+opt+k". Modifiers: cmd, ctrl, opt (or alt), shift.
    public var hotkey: String = "ctrl+opt+k"
    /// Tags cycled with ⇧⇥ in the comment input.
    public var tags: [String] = ["fix", "question", "nit"]
    /// Absolute path to tmux; found automatically when nil.
    public var tmuxPath: String?
    /// tmux socket path for a non-default server (`-S`); nil uses the default socket.
    public var tmuxSocket: String?
    /// Generic tier: how recent a clipboard change must be to count as a selection.
    public var clipboardWindowSeconds: Double = 30

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? d.hotkey
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? d.tags
        tmuxPath = try c.decodeIfPresent(String.self, forKey: .tmuxPath)
        tmuxSocket = try c.decodeIfPresent(String.self, forKey: .tmuxSocket)
        clipboardWindowSeconds = try c.decodeIfPresent(Double.self, forKey: .clipboardWindowSeconds) ?? d.clipboardWindowSeconds
    }

    public static var standardURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kaju/config.json")
    }

    /// Load the config, writing the defaults if there is no file yet.
    public static func load(from url: URL = standardURL) -> Config {
        if let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Config.self, from: data) {
            return c
        }
        let c = Config()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if !FileManager.default.fileExists(atPath: url.path), let data = try? enc.encode(c) {
            try? data.write(to: url)
        }
        return c
    }
}

/// A parsed hotkey such as "ctrl+opt+k".
public struct Hotkey: Equatable {
    public enum Modifier: String { case cmd, ctrl, opt, shift }
    public var key: String
    public var modifiers: Set<Modifier>

    public init?(_ text: String) {
        var mods = Set<Modifier>()
        var key: String?
        for raw in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch raw {
            case "cmd", "command", "⌘": mods.insert(.cmd)
            case "ctrl", "control", "⌃": mods.insert(.ctrl)
            case "opt", "option", "alt", "⌥": mods.insert(.opt)
            case "shift", "⇧": mods.insert(.shift)
            default:
                guard key == nil, raw.count == 1 else { return nil }
                key = raw
            }
        }
        guard let k = key, !mods.isEmpty else { return nil }
        self.key = k
        self.modifiers = mods
    }

    /// Human-readable form, e.g. "⌃⌥K".
    public var display: String {
        var s = ""
        if modifiers.contains(.ctrl) { s += "⌃" }
        if modifiers.contains(.opt) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.cmd) { s += "⌘" }
        return s + key.uppercased()
    }

    /// macOS virtual key code for the key (US layout positions).
    public var keyCode: UInt32? {
        let codes: [String: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31,
            "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
            ";": 41, ",": 43, "/": 44, ".": 47, "'": 39, "`": 50,
        ]
        return codes[key]
    }
}
