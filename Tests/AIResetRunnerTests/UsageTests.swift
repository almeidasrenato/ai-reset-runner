import Foundation
import Testing
@testable import AIResetRunner

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)))
}

// 2026-09-25 23:00 in São Paulo (UTC-3).
private let now = ISO8601DateFormatter().date(from: "2026-09-26T02:00:00Z")!

@Test func claudeCLIActive() throws {
    let text = String(decoding: try fixture("claude-usage.txt"), as: UTF8.self)
    let (session, weekly) = try ClaudeParser.parseCLI(text, now: now)
    #expect(session.usedPercent == 7)
    #expect(session.resetsAt == ISO8601DateFormatter().date(from: "2026-09-26T06:10:00Z"))
    #expect(weekly?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-28T06:00:00Z"))
    #expect(!session.isIdle(now: now))
}

@Test func claudeCLIIdleHasNoReset() throws {
    let text = String(decoding: try fixture("claude-usage-idle.txt"), as: UTF8.self)
    let (session, weekly) = try ClaudeParser.parseCLI(text, now: now)
    #expect(session.resetsAt == nil)
    #expect(session.isIdle(now: now))
    #expect(weekly?.usedPercent == 17)
}

@Test func claudeCLIGarbageThrows() {
    #expect(throws: UsageError.self) { try ClaudeParser.parseCLI("Error: not logged in") }
}

@Test func claudeOAuth() throws {
    let active = try ClaudeParser.parseOAuth(fixture("claude-oauth-active.json"))
    #expect(active.session.usedPercent == 12)
    #expect(!active.session.isIdle(now: now))
    let idle = try ClaudeParser.parseOAuth(fixture("claude-oauth-idle.json"))
    #expect(idle.session.isIdle(now: now))
    #expect(idle.weekly?.usedPercent == 17)
}

@Test func codexIdleWindowIsHypothetical() throws {
    let (session, weekly) = try CodexParser.parse(fixture("codex-idle.json"), now: now)
    #expect(session.resetsAt == nil)
    #expect(session.isIdle(now: now))
    #expect(weekly?.usedPercent == 36)
    #expect(weekly?.resetsAt != nil)
}

@Test func codexActive() throws {
    let (session, weekly) = try CodexParser.parse(fixture("codex-active.json"), now: now)
    #expect(session.usedPercent == 12)
    #expect(session.resetsAt == Date(timeIntervalSince1970: 1790400000))
    #expect(weekly?.usedPercent == 100)
}

@Test func expiredWindowIsIdle() {
    #expect(LimitWindow(usedPercent: 40, resetsAt: now.addingTimeInterval(-1)).isIdle(now: now))
    #expect(!LimitWindow(usedPercent: 0, resetsAt: now.addingTimeInterval(60)).isIdle(now: now))
}

@Test func display() {
    #expect(duration(3 * 3600 + 20 * 60) == "3h20")
    #expect(duration(5 * 60) == "5min")
    #expect(duration(2 * 86400 + 5 * 3600) == "2d 5h")
}

@Test func backoffDoublesAndCaps() {
    #expect(backoff(attempt: 0, retryAfter: 0) == 60)
    #expect(backoff(attempt: 2, retryAfter: nil) == 240)
    #expect(backoff(attempt: 9, retryAfter: nil) == 900)
    #expect(backoff(attempt: 0, retryAfter: 300) == 300)
}

@Test func locateFindsFirstExecutable() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let exe = dir.appendingPathComponent("claude")
    try Data("#!/bin/sh\n".utf8).write(to: exe)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

    let found = Shell.locate("claude", candidates: ["/nonexistent/claude", exe.path], loginShell: false)
    #expect(found?.path == exe.resolvingSymlinksInPath().path)
    #expect(Shell.locate("claude", candidates: ["/nonexistent/claude"], loginShell: false) == nil)
    #expect(Shell.locate("claude", override: exe.path)?.path == exe.path)
    #expect(Shell.locate("claude", override: "/nonexistent/claude") == nil)
}
