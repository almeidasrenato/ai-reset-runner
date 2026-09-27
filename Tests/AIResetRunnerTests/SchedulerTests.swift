import Foundation
import Testing
@testable import AIResetRunner

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func reading(session: LimitWindow, weekly: Double = 20) -> UsageReading {
    UsageReading(session: session, weekly: LimitWindow(usedPercent: weekly, resetsAt: now.addingTimeInterval(86400)),
                 source: "test", raw: "")
}

private let idle = LimitWindow(usedPercent: 0, resetsAt: nil)

@Test func firesWhenNoWindow() {
    #expect(Scheduler.decide(reading: reading(session: idle), readAt: now, lastFire: nil, now: now) == .fire)
}

@Test func firesWhenWindowExpired() {
    let expired = LimitWindow(usedPercent: 80, resetsAt: now.addingTimeInterval(-Scheduler.resetGrace))
    #expect(Scheduler.decide(reading: reading(session: expired), readAt: now, lastFire: nil, now: now) == .fire)
    let justReset = LimitWindow(usedPercent: 100, resetsAt: now.addingTimeInterval(-60))
    #expect(Scheduler.decide(reading: reading(session: justReset), readAt: now, lastFire: nil, now: now) == .skip("window active"))
}

@Test func skipsFreshWindowAtZeroPercent() {
    let fresh = LimitWindow(usedPercent: 0, resetsAt: now.addingTimeInterval(17_900))
    #expect(Scheduler.decide(reading: reading(session: fresh), readAt: now, lastFire: nil, now: now) == .skip("window active"))
}

@Test func skipsWhenWeeklyFull() {
    #expect(Scheduler.decide(reading: reading(session: idle, weekly: 100), readAt: now, lastFire: nil, now: now)
        == .skip("weekly limit reached"))
}

@Test func cooldownBlocksFor4h50() {
    let blocked = Scheduler.decide(reading: reading(session: idle), readAt: now,
                                   lastFire: now.addingTimeInterval(-(4 * 3600 + 49 * 60)), now: now)
    #expect(blocked != .fire)
    #expect(Scheduler.decide(reading: reading(session: idle), readAt: now,
                             lastFire: now.addingTimeInterval(-(4 * 3600 + 51 * 60)), now: now) == .fire)
}

@Test func skipsWithoutFreshReading() {
    #expect(Scheduler.decide(reading: nil, readAt: nil, lastFire: nil, now: now) == .skip("no recent reading"))
    #expect(Scheduler.decide(reading: reading(session: idle), readAt: now.addingTimeInterval(-600), lastFire: nil, now: now)
        == .skip("no recent reading"))
}

@Test func versionCompare() {
    #expect(Updater.isNewer("0.2.0", than: "0.1.0"))
    #expect(Updater.isNewer("0.10.0", than: "0.9.1"))
    #expect(!Updater.isNewer("0.1.0", than: "0.1.0"))
    #expect(!Updater.isNewer("0.1.0", than: "0.2.0"))
}
