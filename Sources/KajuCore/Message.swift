// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// One annotation (a comment): the quoted selection, the comment text and an optional tag.
public struct Annotation: Codable, Equatable {
    public var quote: String
    public var comment: String
    public var tag: String

    public init(quote: String, comment: String, tag: String = "") {
        self.quote = quote
        self.comment = comment
        self.tag = tag
    }

    // Tolerant decoding: a review file written without a quote or tag still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quote = try c.decodeIfPresent(String.self, forKey: .quote) ?? ""
        comment = try c.decode(String.self, forKey: .comment)
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
    }
}

public enum Message {
    /// Quote the selection above the comment, markdown style; the tag prefixes the comment.
    public static func single(_ c: Annotation) -> String {
        let comment = clean(c.comment)
        let body = c.tag.isEmpty ? comment : "[\(clean(c.tag))] \(comment)"
        let quote = clean(c.quote).trimmingCharacters(in: .whitespacesAndNewlines)
        if quote.isEmpty { return body }
        let quoted = quote.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + trimTrailing(String($0)) }
            .joined(separator: "\n")
        return "\(quoted)\n\n\(body)"
    }

    /// A whole review as one numbered message.
    public static func review(_ items: [Annotation]) -> String {
        var parts = ["Review comments (\(items.count)):"]
        for (i, c) in items.enumerated() {
            parts.append("\(i + 1).\n" + single(c))
        }
        return parts.joined(separator: "\n\n")
    }

    /// One line with no control characters at all, so that no shell can
    /// execute it on paste even without bracketed paste mode. Line breaks are
    /// shown as " ⏎ "; every other C0 control character and DEL is dropped.
    public static func singleLine(_ text: String) -> String {
        var out = ""
        var lastWasBreak = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                if !lastWasBreak { out += " ⏎ " }
                lastWasBreak = true
                continue
            }
            lastWasBreak = false
            if scalar.value < 0x20 || scalar.value == 0x7F { continue }
            // C1 controls (U+0080 to U+009F) can also act as escape introducers.
            if (0x80...0x9F).contains(scalar.value) { continue }
            out.unicodeScalars.append(scalar)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Remove control characters except newline and tab, so that terminal
    /// output pasted back (for example a stray ESC[201~) cannot end a
    /// bracketed paste early or inject escape sequences. CR becomes LF.
    public static func clean(_ text: String) -> String {
        var out = ""
        for scalar in text.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars {
            if scalar == "\r" { out += "\n"; continue }
            if scalar == "\n" || scalar == "\t" { out.unicodeScalars.append(scalar); continue }
            if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value) { continue }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    static func trimTrailing(_ s: String) -> String {
        var s = s
        while let last = s.last, last == " " || last == "\t" { s.removeLast() }
        return s
    }

    /// Collapse all whitespace runs to single spaces (for previews and matching).
    public static func squash(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

