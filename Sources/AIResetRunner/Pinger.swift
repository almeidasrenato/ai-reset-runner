import Foundation

struct PingResult: Codable, Equatable {
    var at: Date
    var ok: Bool
    var detail: String
}

/// Creates a throwaway conversation with the cheapest model, sends "ok" and
/// makes sure nothing is left on disk. Both CLIs run in an ephemeral mode, so
/// normally there is nothing to delete; the cleanup is a safety net that only
/// ever touches files created by this ping in this app's workdir.
protocol Pinger: Sendable {
    var name: String { get }
    func ping() async throws -> String
}

struct ClaudePinger: Pinger {
    let name = "Claude"
    var binaryOverride: String? { UserDefaults.standard.string(forKey: "claudePath") }

    func ping() async throws -> String {
        guard let exe = Shell.locate("claude", override: binaryOverride) else {
            throw UsageError.badResponse(L("claude binary not found", "binário claude não encontrado"))
        }
        // `--setting-sources project`: the workdir has no project settings, so the
        // user's hooks/plugins stay out of it. Auth still comes from the Keychain.
        let result = try await Shell.run(exe, [
            "-p", "ok", "--model", "haiku", "--output-format", "json",
            "--no-session-persistence", "--strict-mcp-config", "--setting-sources", "project",
            "--disable-slash-commands", "--tools", "",
        ], timeout: 60)
        log.info("claude ping exit \(result.status) stdout: \(result.out.prefix(400), privacy: .public) stderr: \(result.err.prefix(400), privacy: .public)")
        if result.timedOut { throw UsageError.badResponse(L("timed out after 60s", "timeout de 60s")) }

        struct Output: Decodable { let session_id: String?; let is_error: Bool?; let result: String? }
        let output = try? JSONDecoder().decode(Output.self, from: Data(result.out.utf8))
        if let id = output?.session_id { Self.deleteTranscript(sessionID: id) }
        guard result.status == 0, output?.is_error == false else {
            throw UsageError.badResponse(output?.result ?? String((result.err.isEmpty ? result.out : result.err).prefix(200)))
        }
        return L("haiku replied", "haiku respondeu")
    }

    /// `~/.claude/projects/<workdir with non-alphanumerics as '-'>/<id>.jsonl`.
    static func deleteTranscript(sessionID: String, home: String = NSHomeDirectory()) {
        guard UUID(uuidString: sessionID) != nil else { return }
        let folder = String(Shell.workdir.path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let file = URL(fileURLWithPath: home).appendingPathComponent(".claude/projects/\(folder)/\(sessionID).jsonl")
        if (try? FileManager.default.removeItem(at: file)) != nil {
            log.notice("deleted claude transcript \(file.lastPathComponent, privacy: .public)")
        }
    }
}

struct CodexPinger: Pinger {
    let name = "Codex"
    var binaryOverride: String? { UserDefaults.standard.string(forKey: "codexPath") }
    var model: String { UserDefaults.standard.string(forKey: "codexModel") ?? "gpt-5.6-luna" }

    func ping() async throws -> String {
        guard let exe = Shell.locate("codex", override: binaryOverride) else {
            throw UsageError.badResponse(L("codex binary not found", "binário codex não encontrado"))
        }
        let start = Date()
        // `model_provider=openai` bypasses any proxy set in ~/.codex/config.toml,
        // so the ping lands on the ChatGPT subscription window.
        let result = try await Shell.run(exe, [
            "exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only",
            "-C", Shell.workdir.path, "-m", model,
            "-c", "model_provider=openai", "-c", "model_reasoning_effort=low", "ok",
        ], timeout: 60)
        log.info("codex ping exit \(result.status) stdout: \(result.out.suffix(400), privacy: .public) stderr: \(result.err.suffix(400), privacy: .public)")
        Self.deleteRollouts(since: start)
        if result.timedOut { throw UsageError.badResponse(L("timed out after 60s", "timeout de 60s")) }
        guard result.status == 0 else {
            throw UsageError.badResponse(String((result.err.isEmpty ? result.out : result.err).suffix(200)))
        }
        return L("\(model) replied", "\(model) respondeu")
    }

    /// Only rollouts written after `since` whose session_meta cwd is our workdir.
    static func deleteRollouts(since: Date, home: String = NSHomeDirectory()) {
        let root = URL(fileURLWithPath: home).appendingPathComponent(".codex/sessions")
        let marker = "\"cwd\":\"\(Shell.workdir.path)\""
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.creationDateKey])
        while let file = files?.nextObject() as? URL {
            guard file.lastPathComponent.hasPrefix("rollout-"),
                  let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate, created >= since,
                  let head = try? FileHandle(forReadingFrom: file).read(upToCount: 8192),
                  String(decoding: head, as: UTF8.self).split(separator: "\n").first?.contains(marker) == true
            else { continue }
            try? FileManager.default.removeItem(at: file)
            log.notice("deleted codex rollout \(file.lastPathComponent, privacy: .public)")
        }
    }
}
