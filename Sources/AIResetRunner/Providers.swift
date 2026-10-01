// Endpoints and headers learned from Codenotch (https://github.com/vinzdg/codenotch).
// Copyright (c) 2026 Vinz. MIT License.

import Foundation
import os

let log = Logger(subsystem: "com.local.airesetrunner", category: "app")

/// Reads Claude usage. Primary: `claude "/usage"` — no Keychain prompt, and the
/// CLI refreshes its own token (the Keychain one is often expired after hours
/// idle, which is exactly when a window has expired). Fallback: the OAuth
/// endpoint with the token read through `/usr/bin/security`, which is already
/// on the item's access list, so no prompt either. Tokens are never logged.
struct ClaudeProvider: UsageProvider {
    /// The second account reads through its own `CLAUDE_CONFIG_DIR`, CLI only:
    /// its Keychain item has another name, so there is no OAuth fallback.
    var second = false
    var name: String { second ? ClaudeAccount.secondName : "Claude" }
    var binaryOverride: String? { UserDefaults.standard.string(forKey: "claudePath") }

    func fetch() async throws -> UsageReading {
        if second { return try await fetchCLI() }
        do {
            return try await fetchCLI()
        } catch {
            log.notice("claude /usage failed (\(error.localizedDescription, privacy: .public)), trying OAuth")
            return try await fetchOAuth()
        }
    }

    private func fetchCLI() async throws -> UsageReading {
        guard let exe = Shell.locate("claude", override: binaryOverride) else {
            throw UsageError.badResponse(L("claude binary not found", "binário claude não encontrado"))
        }
        let result = try await Shell.run(exe, ["--print", "--no-session-persistence", "--strict-mcp-config", "/usage"],
                                         env: try ClaudeAccount.env(second: second), timeout: 30)
        // Logged out, `/usage` prints API cost totals instead of subscription limits.
        if result.out.contains("Total cost:") && !result.out.contains("Current session") {
            throw UsageError.needsAuth(second ? L("run: \(ClaudeAccount.loginCommand)", "rode: \(ClaudeAccount.loginCommand)")
                                              : L("run: claude auth login", "rode: claude auth login"))
        }
        let parsed = try ClaudeParser.parseCLI(result.out)
        return UsageReading(session: parsed.session, weekly: parsed.weekly, source: "claude /usage", raw: result.out)
    }

    private func fetchOAuth() async throws -> UsageReading {
        let token = try Self.keychainToken()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let data = try await send(request)
        let parsed = try ClaudeParser.parseOAuth(data)
        return UsageReading(session: parsed.session, weekly: parsed.weekly, source: "OAuth",
                            raw: String(decoding: data, as: UTF8.self))
    }

    private static func keychainToken() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-a", NSUserName(), "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        struct Stored: Decodable {
            struct OAuth: Decodable { let accessToken: String; let expiresAt: Double }
            let claudeAiOauth: OAuth
        }
        guard p.terminationStatus == 0, let stored = try? JSONDecoder().decode(Stored.self, from: data),
              !stored.claudeAiOauth.accessToken.isEmpty
        else { throw UsageError.needsAuth(L("Keychain item 'Claude Code-credentials' missing or unreadable", "item 'Claude Code-credentials' ausente ou ilegível")) }
        guard stored.claudeAiOauth.expiresAt / 1000 > Date().timeIntervalSince1970 else {
            throw UsageError.needsAuth(L("Keychain token expired (run claude once)", "token do Keychain expirado (use o claude uma vez)"))
        }
        return stored.claudeAiOauth.accessToken
    }
}

/// A second Claude login (e.g. a work account) kept in its own config dir,
/// set up once with `CLAUDE_CONFIG_DIR=<dir> claude /login`.
enum ClaudeAccount {
    static let secondName = "Claude 2"
    static let defaultDir = "~/.claude-2"

    static var dirSetting: String {
        get { UserDefaults.standard.string(forKey: "claude2ConfigDir") ?? defaultDir }
        set { UserDefaults.standard.set(newValue, forKey: "claude2ConfigDir") }
    }

    /// Absolute: the CLI does not expand `~` in env vars.
    static var dir: String { (dirSetting.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }

    static var loginCommand: String { "CLAUDE_CONFIG_DIR=\(dirSetting) claude auth login" }

    static func env(second: Bool) throws -> [String: String] {
        guard second else { return [:] }
        guard FileManager.default.fileExists(atPath: dir) else {
            throw UsageError.needsAuth(L("\(dir) not found, run: \(loginCommand)", "\(dir) não existe, rode: \(loginCommand)"))
        }
        return ["CLAUDE_CONFIG_DIR": dir]
    }
}

/// Reads Codex usage from the ChatGPT backend with the token in
/// `~/.codex/auth.json`. Read-only: never refreshes or writes it.
struct CodexProvider: UsageProvider {
    let name = "Codex"
    var authURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")

    func fetch() async throws -> UsageReading {
        struct Auth: Decodable {
            struct Tokens: Decodable { let access_token: String; let account_id: String }
            let tokens: Tokens
        }
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONDecoder().decode(Auth.self, from: data), !auth.tokens.access_token.isEmpty
        else { throw UsageError.needsAuth(L("~/.codex/auth.json missing or has no token", "~/.codex/auth.json ausente ou sem token")) }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(auth.tokens.access_token)", forHTTPHeaderField: "Authorization")
        request.setValue(auth.tokens.account_id, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = try await send(request)
        let parsed = try CodexParser.parse(body)
        return UsageReading(session: parsed.session, weekly: parsed.weekly, source: "wham/usage",
                            raw: String(decoding: body, as: UTF8.self))
    }
}

/// Shared HTTP status handling: 401/403 → needsAuth, 429 → rateLimited.
private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    let http = response as? HTTPURLResponse
    switch http?.statusCode ?? 0 {
    case 200..<300: return data
    case 401, 403: throw UsageError.needsAuth("HTTP \(http?.statusCode ?? 0)")
    case 429: throw UsageError.rateLimited(retryAfter: http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
    case let status: throw UsageError.badResponse("HTTP \(status)")
    }
}
