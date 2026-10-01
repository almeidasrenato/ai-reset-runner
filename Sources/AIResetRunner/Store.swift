// Back-off policy adapted from Codenotch (https://github.com/vinzdg/codenotch).
// Copyright (c) 2026 Vinz. MIT License.

import AppKit
import Observation
import ServiceManagement
import UserNotifications

@MainActor @Observable
final class ProviderState {
    let provider: any UsageProvider
    let pinger: any Pinger
    /// Last good reading, kept across errors.
    var reading: UsageReading?
    var updatedAt: Date?
    var error: String?
    var isLoading = false
    var isPinging = false
    /// Set while waiting to re-read usage after a ping.
    var confirmingUntil: Date?
    var lastPing: PingResult? {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(lastPing), forKey: "lastPing.\(name)") }
    }
    /// Auto-ping when the window expires. Off by default.
    var autoEnabled: Bool {
        didSet { UserDefaults.standard.set(autoEnabled, forKey: "auto.\(name)") }
    }
    /// Last ping attempt, manual or automatic; drives the 4h50 lock.
    var lastFire: Date? {
        didSet { UserDefaults.standard.set(lastFire, forKey: "lastFire.\(name)") }
    }
    /// Off: not read, not pinged, not shown.
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled.\(name)") }
    }
    /// Shown in the panel and the menu bar icon.
    var visible: Bool {
        didSet { UserDefaults.standard.set(visible, forKey: "visible.\(name)") }
    }
    /// Why the scheduler did or did not fire on its last check.
    var autoStatus: String?
    private var rateLimits = 0

    var name: String { provider.name }

    init(_ provider: any UsageProvider, pinger: any Pinger, enabledByDefault: Bool = true) {
        self.provider = provider
        self.pinger = pinger
        lastPing = (UserDefaults.standard.data(forKey: "lastPing.\(provider.name)"))
            .flatMap { try? JSONDecoder().decode(PingResult.self, from: $0) }
        autoEnabled = UserDefaults.standard.bool(forKey: "auto.\(provider.name)")
        lastFire = UserDefaults.standard.object(forKey: "lastFire.\(provider.name)") as? Date
        enabled = UserDefaults.standard.object(forKey: "enabled.\(provider.name)") as? Bool ?? enabledByDefault
        visible = UserDefaults.standard.object(forKey: "visible.\(provider.name)") as? Bool ?? true
    }

    private var backoffKey: String { "backoffUntil.\(name)" }

    func refresh() async {
        if let until = UserDefaults.standard.object(forKey: backoffKey) as? Date, until > Date() {
            error = L("rate limited until \(until.formatted(date: .omitted, time: .shortened))", "aguardando 429 até \(until.formatted(date: .omitted, time: .shortened))")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            reading = try await provider.fetch()
            updatedAt = Date()
            error = nil
            rateLimits = 0
            UserDefaults.standard.removeObject(forKey: backoffKey)
        } catch UsageError.rateLimited(let retryAfter) {
            let wait = backoff(attempt: rateLimits, retryAfter: retryAfter)
            rateLimits += 1
            UserDefaults.standard.set(Date().addingTimeInterval(wait), forKey: backoffKey)
            error = L("429, retrying in \(duration(wait))", "429, nova tentativa em \(duration(wait))")
            log.notice("\(self.name, privacy: .public) rate limited, waiting \(wait)s")
        } catch {
            self.error = error.localizedDescription
            log.error("\(self.name, privacy: .public) fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ping, then re-read usage until a window that started with this ping shows up.
    /// The usage API lags: 45s after a good Claude ping it still showed the old window.
    func ping() async {
        guard !isPinging else { return }
        isPinging = true
        defer { isPinging = false }
        let sentAt = Date()
        lastFire = sentAt
        do {
            let detail = try await pinger.ping()
            lastPing = PingResult(at: Date(), ok: true, detail: "\(detail), confirmando…")
            defer { confirmingUntil = nil }
            var opened = false
            for wait in [45, 75, 120] {
                confirmingUntil = Date().addingTimeInterval(TimeInterval(wait))
                try? await Task.sleep(for: .seconds(wait))
                await refresh()
                // Only a fresh reading whose reset is ~5h after the ping; a failed
                // refresh keeps the old reading, which must not count either way.
                if let at = updatedAt, at > sentAt, let resetsAt = reading?.session.resetsAt,
                   resetsAt > sentAt.addingTimeInterval(4 * 3600) {
                    opened = true
                    break
                }
            }
            // No fresh reading at all: the ping went through, usage just can't confirm it.
            let unconfirmed = !opened && (updatedAt ?? .distantPast) < sentAt
            log.notice("\(self.name, privacy: .public) ping confirmed: \(opened) unreadable: \(unconfirmed)")
            let ok = opened || unconfirmed
            lastPing = PingResult(at: Date(), ok: ok, detail: opened ? L("window opened", "janela aberta")
                : unconfirmed ? L("sent, usage unreadable to confirm", "enviado, uso ilegível para confirmar")
                : L("sent, but no window opened", "enviado, mas a janela não abriu"))
            notify("\(name): \(ok ? L("5h window opened", "janela de 5h aberta") : L("start had no effect", "disparo sem efeito"))", lastPing?.detail ?? "", kind: ok ? .success : .failure)
        } catch {
            // Rejected (e.g. pinged seconds before the server-side reset, or a broken
            // binary): retry in 10 min instead of holding the 4h50 lock.
            lastFire = Date().addingTimeInterval(10 * 60 - Scheduler.cooldown)
            let repeated = lastPing?.ok == false && lastPing?.detail == error.localizedDescription
            lastPing = PingResult(at: Date(), ok: false, detail: error.localizedDescription)
            if !repeated { notify(L("\(name): start failed", "\(name): falha no disparo"), error.localizedDescription, kind: .failure) }
            log.error("\(self.name, privacy: .public) ping failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension ProviderState {
    /// One scheduler cycle: read, decide, maybe ping.
    func tick(simulation: Bool) async {
        guard enabled else { return }
        await refresh()
        guard autoEnabled, !isPinging else { return }
        switch Scheduler.decide(reading: reading, readAt: updatedAt, lastFire: lastFire) {
        case .skip(let reason):
            autoStatus = reason
        case .fire where simulation:
            autoStatus = L("simulation: would start now", "simulação: dispararia agora")
            log.notice("\(self.name, privacy: .public) simulation: would ping now")
        case .fire:
            autoStatus = L("starting automatically", "disparo automático")
            log.notice("\(self.name, privacy: .public) window expired, auto-pinging")
            await ping()
        }
    }
}

/// 60s doubling per consecutive 429, capped at 15 min. `Retry-After` can only
/// raise the wait (Anthropic answers `Retry-After: 0`).
func backoff(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
    min(15 * 60, max(60 * pow(2, Double(min(attempt, 4))), retryAfter ?? 0))
}

@MainActor @Observable
final class Store {
    let claude = ProviderState(ClaudeProvider(), pinger: ClaudePinger())
    /// Opt-in second Claude account (its own CLAUDE_CONFIG_DIR).
    let claude2 = ProviderState(ClaudeProvider(second: true), pinger: ClaudePinger(second: true), enabledByDefault: false)
    let codex = ProviderState(CodexProvider(), pinger: CodexPinger())
    var providers: [ProviderState] { [claude, claude2, codex] }
    /// Mirrors `ClaudeAccount.dirSetting` so the settings text redraws.
    var claude2Dir = ClaudeAccount.dirSetting {
        didSet { ClaudeAccount.dirSetting = claude2Dir }
    }
    var shown: [ProviderState] { providers.filter { $0.enabled && $0.visible } }
    let updater = Updater()
    /// Mirrors `NotificationKind.isOn` so the settings toggles redraw.
    var notificationKinds = Set(NotificationKind.allCases.filter(\.isOn)) {
        didSet { for kind in NotificationKind.allCases { kind.isOn = notificationKinds.contains(kind) } }
    }
    /// Log what auto-ping would do without doing it.
    var simulation = UserDefaults.standard.bool(forKey: "simulation") {
        didSet { UserDefaults.standard.set(simulation, forKey: "simulation") }
    }
    /// UI language. Views are keyed on it so they redraw when it changes.
    var language = Language.current {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            refreshAll()
        }
    }
    /// Follow the system, or force light or dark for the whole app.
    var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            appearance.apply()
        }
    }
    /// Registered as a login item through SMAppService.
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var launchAtLoginError: String?
    private var timer: Timer?

    init() {
        appearance.apply()
        if isAppBundle { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        reschedule()
    }

    /// Every 2 min while any auto-ping is on, every 10 min otherwise.
    /// Call after changing a toggle; also runs a check right away.
    func reschedule() {
        timer?.invalidate()
        let interval: TimeInterval = providers.contains { $0.enabled && $0.autoEnabled } ? 120 : 600
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        refreshAll()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshAll() {
        for state in providers { Task { await state.tick(simulation: simulation) } }
    }
}

/// UNUserNotificationCenter crashes outside a .app (e.g. under `swift test`).
let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"

enum NotificationKind: String, CaseIterable {
    case success, failure, update

    var label: String {
        switch self {
        case .success: return L("Successful start", "Disparo com sucesso")
        case .failure: return L("Failed start", "Falha no disparo")
        case .update: return L("New version available", "Nova versão disponível")
        }
    }
    var key: String { "notify.\(rawValue)" }
    var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// System notification, if that kind is on. Skipped outside an app bundle (e.g. under `swift test`).
func notify(_ title: String, _ body: String, kind: NotificationKind) {
    guard kind.isOn, isAppBundle else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
}

enum Appearance: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return L("System", "Sistema")
        case .light: return L("Light", "Claro")
        case .dark: return L("Dark", "Escuro")
        }
    }

    /// Windows and the popover inherit the app appearance.
    func apply() {
        NSApp?.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
