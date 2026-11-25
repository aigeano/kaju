// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// Event log at ~/Library/Logs/kaju.log, for troubleshooting.
/// Records what happened (helper started, comment sent or refused), never comment text or selections.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/kaju.log")
    private static let queue = DispatchQueue(label: "kaju.log")
    private static let stamp: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()

    private static var rotated = false

    static func info(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            // Keep the log small: once per run, move a log over 1 MB to kaju.log.1.
            if !rotated {
                rotated = true
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                if size > 1_000_000 {
                    let old = url.appendingPathExtension("1")
                    try? FileManager.default.removeItem(at: old)
                    try? FileManager.default.moveItem(at: url, to: old)
                }
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
