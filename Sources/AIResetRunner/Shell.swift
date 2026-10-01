// Binary search list adapted from Codenotch (https://github.com/vinzdg/codenotch).
// Copyright (c) 2026 Vinz. MIT License.

import Foundation

enum Shell {
    static let workdir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIResetRunner/workdir", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A GUI app does not inherit the shell PATH, so look in the usual install
    /// dirs. The Claude desktop app's bundled copy is skipped: it keeps its own
    /// credentials and does not match what the CLI user is logged into.
    static func candidates(for name: String, home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
            .map { "\($0)/\(name)" } + bundled(name, home: home)
    }

    /// The ChatGPT app ships `codex` inside its bundle and moves it between
    /// updates, so search by name instead of trusting a fixed path.
    static func bundled(_ name: String, home: String = NSHomeDirectory()) -> [String] {
        guard name == "codex" else { return [] }
        return ["/Applications/ChatGPT.app", "/Applications/Codex.app", "\(home)/Applications/ChatGPT.app"].flatMap { app in
            let files = FileManager.default.enumerator(atPath: "\(app)/Contents/Resources")
            return (files?.allObjects as? [String] ?? [])
                .filter { ($0 as NSString).lastPathComponent == name }
                .map { "\(app)/Contents/Resources/\($0)" }
        }
    }

    /// Catches wrappers left pointing at a path an app update removed.
    static func runs(_ path: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--version"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if p.isRunning { p.terminate() } }
        p.waitUntilExit()
        return p.terminationReason == .exit && p.terminationStatus == 0
    }

    static func locate(_ name: String, override: String? = nil, candidates: [String]? = nil,
                       loginShell: Bool = true, fileManager: FileManager = .default) -> URL? {
        if let override, !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for path in candidates ?? self.candidates(for: name) where fileManager.isExecutableFile(atPath: path) && runs(path) {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if !resolved.path.contains("/Library/Application Support/Claude/") { return resolved }
        }
        guard loginShell else { return nil }
        // Last resort: ask the user's login shell. `name` is ours, never user input.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(name)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && fileManager.isExecutableFile(atPath: path) && runs(path) ? URL(fileURLWithPath: path) : nil
    }

    struct Result { let status: Int32; let out: String; let err: String; let timedOut: Bool }

    /// Runs `exe` in `workdir`, killing it after `timeout`.
    static func run(_ exe: URL, _ args: [String], env extra: [String: String] = [:], timeout: TimeInterval) async throws -> Result {
        try await Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.currentDirectoryURL = workdir
            var env = ProcessInfo.processInfo.environment
            // Its own dir first so an nvm-installed CLI finds its `node`.
            env["PATH"] = ([exe.deletingLastPathComponent().path] + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
                .joined(separator: ":")
            env.merge(extra) { $1 }
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            try p.run()

            let timedOut = Flag()
            let killer = DispatchWorkItem { if p.isRunning { timedOut.set(); p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            // Drain both pipes concurrently so a chatty process cannot block on a full pipe.
            async let o = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
            async let e = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
            let (od, ed) = await (o, e)
            p.waitUntilExit()
            killer.cancel()
            return Result(status: p.terminationStatus, out: String(decoding: od, as: UTF8.self),
                          err: String(decoding: ed, as: UTF8.self), timedOut: timedOut.value)
        }.value
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}
