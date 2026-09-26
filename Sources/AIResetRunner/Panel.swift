import AppKit
import SwiftUI

/// Warm, system-following palette: sage accent, terracotta only for a used-up limit.
enum Theme {
    static let accent = Color(light: 0x4C7658, dark: 0x9BC2A1)
    static let warning = Color(light: 0xB0503A, dark: 0xE8937C)
    static let track = Color.primary.opacity(0.09)
    static let groupFill = Color.primary.opacity(0.035)
    static let hairline = Color.primary.opacity(0.08)

    static func usage(_ percent: Double) -> Color { percent >= 100 ? warning : accent }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light) })
    }
}

extension View {
    /// Soft grouped surface, like a System Settings section.
    func group(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    /// Shared look for the panel and the settings window.
    func appStyle() -> some View {
        self.tint(Theme.accent)
    }
}

/// Native mini switch in the accent color.
extension View {
    func softSwitch() -> some View {
        self.labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }
}

struct Panel: View {
    let store: Store
    var openSettings: () -> Void = {}

    var body: some View {
        TimelineView(.periodic(from: .now, by: store.providers.contains { $0.isPinging } ? 1 : 30)) { context in
            VStack(spacing: 8) {
                header
                if store.shown.isEmpty {
                    Text(L("No provider enabled. Turn on Claude or Codex in Settings.", "Nenhum provedor ativo. Ative o Claude ou o Codex em Configurações."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .group()
                }
                ForEach(store.shown, id: \.name) { ProviderCard(state: $0, now: context.date, onAutoChange: store.reschedule) }
                footer
            }
            .padding(12)
        }
        .frame(width: 320)
        .appStyle()
        .id(store.language)
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text("AI ResetRunner").font(.system(size: 13, weight: .semibold))
            Spacer()
            let loading = store.providers.contains { $0.isLoading }
            IconButton(symbol: "arrow.clockwise", help: L("Check now", "Verificar agora")) { store.refreshAll() }
                .rotationEffect(.degrees(loading ? 360 : 0))
                .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
            IconButton(symbol: "gearshape", help: L("Settings", "Configurações"), action: openSettings)
                .overlay(alignment: .topTrailing) {
                    if store.updater.available != nil { Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(x: -5, y: 5) }
                }
        }
        .padding(.leading, 4)
    }

    private var footer: some View {
        HStack {
            Button(L("Copy raw data", "Copiar dados brutos")) {
                let text = store.providers.map { "## \($0.name) (\($0.reading?.source ?? "-"))\n\($0.reading?.raw ?? $0.error ?? "")" }
                    .joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            if store.simulation {
                Spacer()
                Text(L("Simulation", "Simulação")).foregroundStyle(Theme.accent)
            }
            Spacer()
            Button(L("Quit", "Sair")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
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
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ProviderCard: View {
    let state: ProviderState
    let now: Date
    let onAutoChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(state.name).font(.system(size: 14, weight: .semibold))
                Spacer()
                pingButton
            }
            LimitRow(title: L("Session · 5h", "Sessão · 5h"), window: state.reading?.session, idleText: L("No active window", "Sem janela ativa"), now: now)
            LimitRow(title: L("Weekly", "Semanal"), window: state.reading?.weekly, idleText: L("No active limit", "Sem limite ativo"), now: now)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            HStack {
                Text(L("Auto-start", "Auto-disparo")).font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(get: { state.autoEnabled }, set: {
                    state.autoEnabled = $0
                    state.autoStatus = nil
                    onAutoChange()
                }))
                .softSwitch()
            }
            .help(L("Starts a window by itself when none is active (at most once every 4h50)", "Dispara sozinho quando não houver janela de 5h ativa (no máximo 1 vez a cada 4h50)"))
            status
        }
        .group()
    }

    private var pingLabel: String {
        if let until = state.confirmingUntil { return L("Confirming \(max(0, Int(until.timeIntervalSince(now))))s", "Confirmando \(max(0, Int(until.timeIntervalSince(now))))s") }
        if state.isPinging { return L("Sending", "Enviando") }
        return L("Start now", "Disparar")
    }

    private var pingButton: some View {
        Button { Task { await state.ping() } } label: {
            HStack(spacing: 5) {
                if state.isPinging { ProgressView().controlSize(.mini) }
                Text(pingLabel).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.accent.opacity(0.13), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.isPinging)
        .help(L("Opens the 5h window now with a tiny message, then re-reads usage after 45s to confirm", "Abre a janela de 5h agora com uma mensagem mínima; depois espera 45s e relê o uso para confirmar"))
    }

    @ViewBuilder private var status: some View {
        let lines = [
            state.autoEnabled ? L("Auto: \(state.autoStatus ?? L("waiting for a reading", "aguardando leitura"))", "Auto: \(state.autoStatus ?? "aguardando leitura")") : nil,
            state.lastPing.map { ping in
                L("Last start \(ping.at.formatted(date: .omitted, time: .shortened)) · \(ping.detail)", "Último disparo \(ping.at.formatted(date: .omitted, time: .shortened)) · \(ping.detail)")
            },
        ].compactMap { $0 }
        if state.error != nil || !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if let error = state.error {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Theme.warning)
                }
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.top, -4)
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Text(active ? L("resets in \(duration(window!.resetsAt!.timeIntervalSince(now)))", "reseta em \(duration(window!.resetsAt!.timeIntervalSince(now)))") : idleText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window == nil ? "—" : "\(Int(percent.rounded()))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(percent >= 100 ? AnyShapeStyle(Theme.warning) : active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.usage(percent).opacity(active ? 1 : 0.45))
                        .frame(width: geo.size.width * min(percent / 100, 1))
                }
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.4), value: percent)
        }
        .font(.system(size: 12))
    }
}
