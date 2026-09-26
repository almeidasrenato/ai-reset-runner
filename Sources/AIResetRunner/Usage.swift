// Parsing adapted from Codenotch (https://github.com/vinzdg/codenotch).
// Copyright (c) 2026 Vinz. MIT License.

import Foundation

/// One limit window. `resetsAt == nil` means no window is running.
struct LimitWindow: Equatable {
    var usedPercent: Double
    var resetsAt: Date?

    /// Nothing running: the previous window expired (or never started).
    /// Not "usage == 0": a freshly opened window also reads ~0%.
    func isIdle(now: Date = Date()) -> Bool {
        guard let resetsAt else { return true }
        return resetsAt <= now
    }
}

struct UsageReading: Equatable {
    var session: LimitWindow
    var weekly: LimitWindow?
    var source: String
    var raw: String
}

enum UsageError: LocalizedError {
    case needsAuth(String)
    case rateLimited(retryAfter: TimeInterval?)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .needsAuth(let why): return L("not signed in: \(why)", "sem login: \(why)")
        case .rateLimited: return L("rate limited (429)", "limite de requisições (429)")
        case .badResponse(let why): return L("bad response: \(why)", "resposta inválida: \(why)")
        }
    }
}

protocol UsageProvider: Sendable {
    var name: String { get }
    func fetch() async throws -> UsageReading
}

// MARK: - Claude

enum ClaudeParser {
    /// `claude "/usage"` output, e.g.
    ///     Current session: 7% used · resets Sep 26 at 3:10am (America/Sao_Paulo)
    ///     Current week (all models): 17% used · resets Sep 28 at 3am (America/Sao_Paulo)
    private static let line = try! NSRegularExpression(
        pattern: #"^Current (?:(session)|week \(([^)]+)\)):\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s*(.+?))?\s*$"#,
        options: [.anchorsMatchLines]
    )

    static func parseCLI(_ text: String, now: Date = Date()) throws -> (session: LimitWindow, weekly: LimitWindow?) {
        var session: LimitWindow?
        var weekly: LimitWindow?
        for match in line.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func group(_ i: Int) -> String? {
                Range(match.range(at: i), in: text).map { String(text[$0]) }
            }
            guard let percent = group(3).flatMap(Double.init) else { continue }
            let window = LimitWindow(usedPercent: percent, resetsAt: group(4).flatMap { resetDate(from: $0, now: now) })
            if group(1) != nil {
                session = session ?? window
            } else if group(2)?.lowercased() == "all models" {
                weekly = weekly ?? window
            }
        }
        guard let session else { throw UsageError.badResponse(L("'Current session' line missing", "linha 'Current session' ausente")) }
        return (session, weekly)
    }

    /// `Sep 7 at 2:59pm (Asia/Jakarta)` → Date. No year is printed, so pick the
    /// candidate nearest `now` (handles New Year's Eve both ways).
    static func resetDate(from text: String, now: Date) -> Date? {
        var stamp = text.trimmingCharacters(in: .whitespaces)
        var zone = TimeZone.current
        // Zone first: `America/...` carries an "am" of its own.
        if let open = stamp.lastIndex(of: "("), stamp.hasSuffix(")") {
            zone = TimeZone(identifier: String(stamp[stamp.index(after: open)...].dropLast())) ?? zone
            stamp = String(stamp[..<open]).trimmingCharacters(in: .whitespaces)
        }
        stamp = stamp.replacingOccurrences(of: "am", with: "AM").replacingOccurrences(of: "pm", with: "PM")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        // Minutes are dropped on the hour: `3:10am` but `3am`.
        guard let parsed = ["MMM d 'at' h:mma", "MMM d 'at' ha"].lazy.compactMap({ format -> Date? in
            formatter.dateFormat = format
            return formatter.date(from: stamp)
        }).first else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
        let year = calendar.component(.year, from: now)
        return [year - 1, year, year + 1].compactMap { y -> Date? in
            parts.year = y
            return calendar.date(from: parts)
        }.min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }

    /// `GET /api/oauth/usage` body: `five_hour`/`seven_day { utilization, resets_at }`.
    static func parseOAuth(_ data: Data) throws -> (session: LimitWindow, weekly: LimitWindow?) {
        struct Body: Decodable {
            struct W: Decodable { let utilization: Double?; let resetsAt: String? }
            let fiveHour: W?
            let sevenDay: W?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body: Body
        do { body = try decoder.decode(Body.self, from: data) } catch {
            throw UsageError.badResponse(L("Claude JSON: \(error.localizedDescription)", "JSON do Claude: \(error.localizedDescription)"))
        }
        func window(_ w: Body.W?) -> LimitWindow? {
            guard let w else { return nil }
            return LimitWindow(usedPercent: w.utilization ?? 0, resetsAt: w.resetsAt.flatMap(isoDate))
        }
        // Absent five_hour == no window running.
        return (window(body.fiveHour) ?? LimitWindow(usedPercent: 0, resetsAt: nil), window(body.sevenDay))
    }

    static func isoDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

// MARK: - Codex

enum CodexParser {
    /// `GET /backend-api/wham/usage`. Idle windows are NOT null here: the API
    /// reports a hypothetical window that would start now, i.e.
    /// `reset_after_seconds >= limit_window_seconds` (observed 18001 vs 18000).
    /// A running window always counts down below its length.
    static func parse(_ data: Data, now: Date = Date()) throws -> (session: LimitWindow, weekly: LimitWindow?) {
        struct Body: Decodable {
            struct Limits: Decodable { let primary_window: W?; let secondary_window: W? }
            struct W: Decodable {
                let used_percent: Double?
                let limit_window_seconds: Double?
                let reset_after_seconds: Double?
                let reset_at: Double?
            }
            let rate_limit: Limits?
        }
        let body: Body
        do { body = try JSONDecoder().decode(Body.self, from: data) } catch {
            throw UsageError.badResponse(L("Codex JSON: \(error.localizedDescription)", "JSON do Codex: \(error.localizedDescription)"))
        }
        func window(_ w: Body.W?) -> LimitWindow? {
            guard let w else { return nil }
            if let after = w.reset_after_seconds, let length = w.limit_window_seconds, after >= length - 5 {
                return LimitWindow(usedPercent: w.used_percent ?? 0, resetsAt: nil)
            }
            let resetsAt = w.reset_at.map { Date(timeIntervalSince1970: $0) }
                ?? w.reset_after_seconds.map { now.addingTimeInterval($0) }
            return LimitWindow(usedPercent: w.used_percent ?? 0, resetsAt: resetsAt)
        }
        return (window(body.rate_limit?.primary_window) ?? LimitWindow(usedPercent: 0, resetsAt: nil),
                window(body.rate_limit?.secondary_window))
    }
}

// MARK: - Display

func duration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    let (d, h, m) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return String(format: "%dh%02d", h, m) }
    return "\(m)min"
}
