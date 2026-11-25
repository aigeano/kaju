// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Foundation

/// Runs external programs. Tests replace `runner` to fake `ps`, `tmux` and `osascript`.
public struct Shell {
    public var runner: (_ path: String, _ args: [String], _ input: String?) -> (status: Int32, out: String)?

    public init(runner: @escaping (String, [String], String?) -> (status: Int32, out: String)?) {
        self.runner = runner
    }

    /// Standard output if the program exited with status 0, else nil.
    public func run(_ path: String, _ args: [String], input: String? = nil) -> String? {
        guard let r = runner(path, args, input), r.status == 0 else { return nil }
        return r.out
    }

    public static let system = Shell { path, args, input in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let inPipe = Pipe()
        if input != nil { p.standardInput = inPipe }
        do { try p.run() } catch { return nil }
        if let input {
            inPipe.fileHandleForWriting.write(input.data(using: .utf8) ?? Data())
            try? inPipe.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
