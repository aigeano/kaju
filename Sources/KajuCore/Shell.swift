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

    /// Real processes, terminated after `timeout` seconds so that a hung program
    /// (an unanswered permission prompt, a stuck tmux server) cannot block kaju.
    public static let system = Shell.real(timeout: 5)

    public static func real(timeout: TimeInterval) -> Shell { Shell { path, args, input in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let inPipe = Pipe()
        if input != nil { p.standardInput = inPipe }
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        if let input {
            try? inPipe.fileHandleForWriting.write(contentsOf: input.data(using: .utf8) ?? Data())
            try? inPipe.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        if p.terminationReason == .uncaughtSignal { return (-1, "") }  // timed out
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    } }
}
