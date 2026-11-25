// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// A review on disk: one JSON file per open review, rewritten on every change,
/// so reviews survive a restart of kaju. The file is deleted when the review
/// is sent or discarded.
public struct ReviewFile: Codable, Equatable {
    /// Which adapter and target the review belongs to (see `Target.key`).
    public var key: String
    /// Human-readable label, e.g. the pane or tab name.
    public var label: String
    public var items: [Annotation]

    public init(key: String, label: String, items: [Annotation]) {
        self.key = key
        self.label = label
        self.items = items
    }
}

public struct ReviewStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/kaju/reviews`
    public static var standard: ReviewStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ReviewStore(directory: base.appendingPathComponent("kaju/reviews", isDirectory: true))
    }

    func url(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }

    public func save(_ review: ReviewFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(review)
        try data.write(to: url(for: review.key), options: .atomic)
    }

    public func load(key: String) -> ReviewFile? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(ReviewFile.self, from: data)
    }

    public func delete(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// Every saved review, for restoring after a restart.
    public func all() -> [ReviewFile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { u in
            (try? Data(contentsOf: u)).flatMap { try? JSONDecoder().decode(ReviewFile.self, from: $0) }
        }
    }

    /// One-time import of reviews saved by the iTerm2 prototype (plain arrays of
    /// comments, one file per iTerm2 session id). Imported files are removed.
    public func importPrototype(from dir: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var n = 0
        for u in files where u.pathExtension == "json" {
            guard let data = try? Data(contentsOf: u),
                  let items = try? JSONDecoder().decode([Annotation].self, from: data), !items.isEmpty else { continue }
            let sid = u.deletingPathExtension().lastPathComponent
            if (try? save(ReviewFile(key: "iterm2:" + sid, label: "imported review", items: items))) != nil {
                try? FileManager.default.removeItem(at: u)
                n += 1
            }
        }
        return n
    }
}
