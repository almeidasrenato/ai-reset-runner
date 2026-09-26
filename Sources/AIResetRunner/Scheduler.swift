import Foundation

/// Whether an automatic ping should go out now. Pure, so every rule is tested.
enum Scheduler {
    enum Decision: Equatable {
        case fire
        case skip(String)
    }

    /// At most one ping per provider in this span, manual or automatic.
    static let cooldown: TimeInterval = 4 * 3600 + 50 * 60
    /// Decide only on a reading from this cycle, never on a stale cached one.
    static let maxReadingAge: TimeInterval = 5 * 60

    static func decide(reading: UsageReading?, readAt: Date?, lastFire: Date?, now: Date = Date()) -> Decision {
        guard let reading, let readAt, now.timeIntervalSince(readAt) <= maxReadingAge else {
            return .skip(L("no recent reading", "sem leitura recente"))
        }
        // Not "usage == 0": a window opened a minute ago also reads 0%.
        guard reading.session.isIdle(now: now) else { return .skip(L("window active", "janela ativa")) }
        if let weekly = reading.weekly, weekly.usedPercent >= 100 { return .skip(L("weekly limit reached", "limite semanal cheio")) }
        if let lastFire, now.timeIntervalSince(lastFire) < cooldown {
            let until = lastFire.addingTimeInterval(cooldown)
            return .skip(L("locked until \(until.formatted(date: .omitted, time: .shortened))", "trava até \(until.formatted(date: .omitted, time: .shortened))"))
        }
        return .fire
    }
}
