import AppKit
import SwiftUI

enum Theme {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let card = Color(red: 0.10, green: 0.115, blue: 0.14)
    static let cardBorder = Color.white.opacity(0.05)
    static let track = Color.white.opacity(0.08)
    static let primary = Color(red: 0.91, green: 0.93, blue: 0.95)
    static let secondary = Color(red: 0.55, green: 0.59, blue: 0.65)
    static let accent = Color(red: 0.49, green: 0.73, blue: 1.0)
    static let accentFill = Color(red: 0.19, green: 0.29, blue: 0.43)
    static let warning = Color(red: 1.0, green: 0.55, blue: 0.50)

    /// Blue everywhere; only a limit that is used up turns red.
    static func usage(_ percent: Double) -> Color { percent >= 100 ? warning : accent }
}

extension View {
    /// Rounded card on the panel background.
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder))
    }

    /// Shared look for the panel and the settings window.
    func appStyle() -> some View {
        self.fontDesign(.rounded)
            .foregroundStyle(Theme.primary)
            .tint(Theme.accent)
            .environment(\.colorScheme, .dark)
    }
}

/// The app mark: blue disc with a reset arrow.
struct AppMark: View {
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(Theme.background)
            .frame(width: size, height: size)
            .background(Theme.accent, in: Circle())
    }
}

struct Panel: View {
    let store: Store
    var openSettings: () -> Void = {}

    var body: some View {
        TimelineView(.periodic(from: .now, by: store.providers.contains { $0.isPinging } ? 1 : 30)) { context in
            VStack(spacing: 10) {
                header
                if store.shown.isEmpty {
                    Text(L("No provider enabled. Turn on Claude or Codex in Settings.", "Nenhum provedor ativo. Ative o Claude ou o Codex em Configurações."))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .card()
                }
                ForEach(store.shown, id: \.name) { ProviderCard(state: $0, now: context.date, onAutoChange: store.reschedule) }
                footer
            }
            .padding(14)
        }
        .frame(width: 350)
        .background(Theme.background)
        .appStyle()
        .id(store.language)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppMark()
            Text("AI ResetRunner").font(.system(size: 16, weight: .bold))
            Spacer()
            let loading = store.providers.contains { $0.isLoading }
            IconButton(symbol: "arrow.clockwise", help: L("Check now", "Verificar agora")) { store.refreshAll() }
                .rotationEffect(.degrees(loading ? 360 : 0))
                .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
            IconButton(symbol: "gearshape", help: L("Settings", "Configurações"), action: openSettings)
            .overlay(alignment: .topTrailing) {
                if store.updater.available != nil { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack {
            Button {
                let text = store.providers.map { "## \($0.name) (\($0.reading?.source ?? "-"))\n\($0.reading?.raw ?? $0.error ?? "")" }
                    .joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label(L("Copy raw data", "Copiar dados brutos"), systemImage: "doc.on.doc")
            }
            if store.simulation {
                Spacer()
                Label(L("simulation", "simulação"), systemImage: "flask").foregroundStyle(Theme.accent)
            }
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Label(L("Quit", "Sair"), systemImage: "rectangle.portrait.and.arrow.right").labelStyle(TrailingIcon())
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Flat blue switch. Drawn in SwiftUI (not NSSwitch) so it matches the theme.
struct BlueSwitch: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Capsule()
                .fill(configuration.isOn ? Theme.accent : Theme.track)
                .frame(width: 30, height: 17)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).padding(2).shadow(radius: 1, y: 0.5)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                .contentShape(Capsule())
                .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
                .accessibilityAddTraits(.isButton)
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

struct ProviderCard: View {
    let state: ProviderState
    let now: Date
    let onAutoChange: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            UsageRing(session: state.reading?.session, now: now)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(state.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    pingButton
                }
                LimitRow(title: L("Session · 5h", "Sessão · 5h"), window: state.reading?.session, idleText: L("no active window", "sem janela ativa"), now: now)
                LimitRow(title: L("Weekly", "Semanal"), window: state.reading?.weekly, idleText: L("no active limit", "sem limite ativo"), now: now)
                HStack {
                    Text(L("Auto-start", "Auto-disparo")).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle("", isOn: Binding(get: { state.autoEnabled }, set: {
                        state.autoEnabled = $0
                        state.autoStatus = nil
                        onAutoChange()
                    }))
                    .labelsHidden()
                    .toggleStyle(BlueSwitch())
                }
                .help(L("Starts a window by itself when none is active (at most once every 4h50)", "Dispara sozinho quando não houver janela de 5h ativa (no máximo 1 vez a cada 4h50)"))
                status
            }
        }
        .card()
    }

    private var pingLabel: String {
        if let until = state.confirmingUntil { return L("Confirming \(max(0, Int(until.timeIntervalSince(now))))s", "Confirmando \(max(0, Int(until.timeIntervalSince(now))))s") }
        if state.isPinging { return L("Sending", "Enviando") }
        return L("Start now", "Disparar")
    }

    private var pingButton: some View {
        Button { Task { await state.ping() } } label: {
            HStack(spacing: 5) {
                if state.isPinging {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 9))
                }
                Text(pingLabel).monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Theme.accentFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.isPinging)
        .help(L("Opens the 5h window now with a tiny message, then re-reads usage after 45s to confirm", "Abre a janela de 5h agora com uma mensagem mínima; depois espera 45s e relê o uso para confirmar"))
    }

    @ViewBuilder private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Theme.warning)
            }
            if state.autoEnabled {
                Label(L("Auto: \(state.autoStatus ?? L("waiting for a reading", "aguardando leitura"))", "Auto: \(state.autoStatus ?? "aguardando leitura")"), systemImage: "wand.and.stars")
            }
            if let ping = state.lastPing {
                Label(L("Last start \(ping.at.formatted(date: .omitted, time: .shortened)) · \(ping.detail)", "Último disparo \(ping.at.formatted(date: .omitted, time: .shortened)) · \(ping.detail)"),
                      systemImage: ping.ok ? "clock" : "xmark.circle")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondary)
        .lineLimit(2)
    }
}

struct LimitRow: View {
    let title: String
    let window: LimitWindow?
    let idleText: String
    let now: Date

    var body: some View {
        let active = window.map { !$0.isIdle(now: now) } ?? false
        let percent = window?.usedPercent ?? 0
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Theme.secondary)
                Spacer()
                Text(window == nil ? "—" : "\(Int(percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(active ? Theme.usage(percent) : Theme.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.usage(percent)).frame(width: geo.size.width * min(percent / 100, 1))
                }
            }
            .frame(height: 5)
            Text(active ? L("resets in \(duration(window!.resetsAt!.timeIntervalSince(now)))", "reseta em \(duration(window!.resetsAt!.timeIntervalSince(now)))") : idleText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
        }
        .font(.system(size: 12))
    }
}

/// 5h session usage. Dashed ring = no active window.
struct UsageRing: View {
    let session: LimitWindow?
    let now: Date

    var body: some View {
        let active = session.map { !$0.isIdle(now: now) } ?? false
        let percent = session?.usedPercent ?? 0
        ZStack {
            Circle().stroke(Theme.track, style: StrokeStyle(lineWidth: 6, dash: active ? [] : [3, 5]))
            if active {
                Circle().trim(from: 0, to: max(percent / 100, 0.005))
                    .stroke(Theme.usage(percent), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(active ? "\(Int(percent.rounded()))%" : "—")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
        }
        .padding(3)
    }
}
