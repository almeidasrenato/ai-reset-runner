import AppKit
import SwiftUI

struct SettingsView: View {
    let store: Store
    var version = Updater.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Settings", "Configurações")).font(.system(size: 18, weight: .bold))
                    Text(L("AI ResetRunner · version \(version)", "AI ResetRunner · versão \(version)")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.bottom, 4)

            section(L("General", "Geral"), "slider.horizontal.3") {
                HStack {
                    Text(L("Language", "Idioma"))
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(Language.allCases, id: \.self) { lang in
                            let selected = store.language == lang
                            Button { store.language = lang } label: {
                                Text(lang == .en ? "English" : "Português")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(selected ? .white : Theme.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(selected ? Theme.accentFill : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Theme.track, in: Capsule())
                }
                divider
                row(L("Open at login", "Abrir ao iniciar o Mac"), get: { store.launchAtLogin }, set: store.setLaunchAtLogin)
                if let error = store.launchAtLoginError {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.warning)
                }
                divider
                row(L("Simulation mode", "Modo simulação"), detail: L("Auto-start only logs what it would do", "O auto-disparo só registra o que faria"), get: { store.simulation }, set: {
                    store.simulation = $0
                    store.refreshAll()
                })
            }

            section(L("Providers", "Provedores"), "square.stack.3d.up") {
                ForEach(Array(store.providers.enumerated()), id: \.element.name) { index, state in
                    if index > 0 { divider }
                    HStack(spacing: 14) {
                        Text(state.name).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        labeledSwitch(L("Enabled", "Ativo"), get: { state.enabled }, set: {
                            state.enabled = $0
                            store.reschedule()
                        })
                        labeledSwitch(L("Show", "Mostrar"), get: { state.visible }, set: { state.visible = $0 })
                            .disabled(!state.enabled)
                    }
                }
                Text(L("Disabled: no reading, no starts. Hidden: keeps working, just not shown in the panel.", "Desativado não lê o uso nem dispara. Oculto continua funcionando, só não aparece no painel."))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(L("Notifications", "Notificações"), "bell") {
                ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { divider }
                    row(kind.label, get: { store.notificationKinds.contains(kind) }, set: {
                        if $0 { store.notificationKinds.insert(kind) } else { store.notificationKinds.remove(kind) }
                    })
                }
                pill(L("macOS notification settings", "Ajustes de notificação do macOS"), "arrow.up.forward.app") {
                    let id = Bundle.main.bundleIdentifier ?? ""
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                }
            }

            section(L("Updates", "Atualizações"), "arrow.down.circle") {
                let updater = store.updater
                row(L("Check for new versions", "Procurar novas versões"), detail: L("Once a day, on GitHub", "Uma vez por dia, no GitHub"), get: { updater.autoCheck }, set: { updater.autoCheck = $0 })
                divider
                row(L("Install automatically", "Instalar sozinho"), get: { updater.autoInstall }, set: { updater.autoInstall = $0 })
                    .disabled(!updater.autoCheck)
                HStack {
                    Text(updater.status ?? L("Version \(version)", "Versão \(version)"))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(2)
                    Spacer()
                    if updater.isBusy {
                        ProgressView().controlSize(.small)
                    } else if let available = updater.available {
                        pill(L("Install \(available.version)", "Instalar \(available.version)"), "arrow.down.to.line", filled: true) { Task { await updater.install() } }
                    } else {
                        pill(L("Check now", "Verificar agora"), "arrow.clockwise") { Task { await updater.check() } }
                    }
                }
                .padding(.top, 4)
            }

            section(L("Project", "Projeto"), "info.circle") {
                HStack(spacing: 8) {
                    pill(L("Repository", "Repositório"), "chevron.left.forwardslash.chevron.right") { NSWorkspace.shared.open(Updater.repoURL) }
                    pill(L("What's new", "Novidades"), "sparkles") { NSWorkspace.shared.open(Updater.repoURL.appendingPathComponent("releases")) }
                    pill(L("Report a bug", "Reportar erro"), "ladybug") { NSWorkspace.shared.open(Updater.repoURL.appendingPathComponent("issues/new")) }
                }
            }
        }
        .font(.system(size: 13))
    }

    private var divider: some View {
        Rectangle().fill(Theme.cardBorder).frame(height: 1)
    }

    private func section<Content: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 10, content: content).card(padding: 14)
        }
    }

    private func row(_ title: String, detail: String? = nil, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            }
            Spacer()
            Toggle("", isOn: Binding(get: get, set: set)).labelsHidden().toggleStyle(BlueSwitch())
        }
    }

    private func labeledSwitch(_ title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Toggle("", isOn: Binding(get: get, set: set)).labelsHidden().toggleStyle(BlueSwitch())
        }
    }

    private func pill(_ title: String, _ icon: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filled ? .white : Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(filled ? Theme.accentFill : Theme.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
