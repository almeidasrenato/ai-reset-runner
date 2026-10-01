import AppKit
import SwiftUI

struct SettingsView: View {
    let store: Store
    var version = Updater.current

    /// Header stays put; the sections scroll under it.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Settings", "Configurações")).font(.system(size: 17, weight: .semibold))
                    Text(L("AI ResetRunner · version \(version)", "AI ResetRunner · versão \(version)")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(EdgeInsets(top: 34, leading: 20, bottom: 12, trailing: 20))
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            ScrollView {
                sections.padding(EdgeInsets(top: 6, leading: 20, bottom: 20, trailing: 20))
            }
        }
        .font(.system(size: 13))
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(L("General", "Geral")) {
                HStack {
                    Text(L("Language", "Idioma"))
                    Spacer()
                    Picker("", selection: Binding(get: { store.language }, set: { store.language = $0 })) {
                        ForEach(Language.allCases, id: \.self) { Text($0 == .en ? "English" : "Português").tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                divider
                HStack {
                    Text(L("Appearance", "Aparência"))
                    Spacer()
                    Picker("", selection: Binding(get: { store.appearance }, set: { store.appearance = $0 })) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
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

            section(L("Providers", "Provedores")) {
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
                    if state === store.claude2 && state.enabled { secondAccount }
                }
                Text(L("Disabled: no reading, no starts. Hidden: keeps working, just not shown in the panel.", "Desativado não lê o uso nem dispara. Oculto continua funcionando, só não aparece no painel."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(L("Notifications", "Notificações")) {
                ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { divider }
                    row(kind.label, get: { store.notificationKinds.contains(kind) }, set: {
                        if $0 { store.notificationKinds.insert(kind) } else { store.notificationKinds.remove(kind) }
                    })
                }
                divider
                link(L("Open macOS notification settings", "Abrir ajustes de notificação do macOS")) {
                    let id = Bundle.main.bundleIdentifier ?? ""
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                }
            }

            section(L("Updates", "Atualizações")) {
                let updater = store.updater
                row(L("Check for new versions", "Procurar novas versões"), detail: L("Once a day, on GitHub", "Uma vez por dia, no GitHub"), get: { updater.autoCheck }, set: { updater.autoCheck = $0 })
                divider
                row(L("Install automatically", "Instalar sozinho"), get: { updater.autoInstall }, set: { updater.autoInstall = $0 })
                    .disabled(!updater.autoCheck)
                HStack {
                    Text(updater.status ?? L("Version \(version)", "Versão \(version)"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if updater.isBusy {
                        ProgressView().controlSize(.small)
                    } else if let available = updater.available {
                        Button(L("Install \(available.version)", "Instalar \(available.version)")) { Task { await updater.install() } }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Button(L("Check now", "Verificar agora")) { Task { await updater.check() } }
                            .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }

            section(L("Project", "Projeto")) {
                HStack(spacing: 18) {
                    link(L("Repository", "Repositório")) { NSWorkspace.shared.open(Updater.repoURL) }
                    link(L("Release notes", "Notas de versão")) { NSWorkspace.shared.open(Updater.repoURL.appendingPathComponent("releases")) }
                    link(L("Report a bug", "Reportar erro")) { NSWorkspace.shared.open(Updater.repoURL.appendingPathComponent("issues/new")) }
                }
            }
        }
    }

    /// Config dir of the second Claude account, plus the one-time login command.
    private var secondAccount: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Config folder", "Pasta de config")).font(.system(size: 12)).foregroundStyle(.secondary)
                TextField(ClaudeAccount.defaultDir, text: Binding(get: { store.claude2Dir }, set: { store.claude2Dir = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { store.reschedule() }
            }
            Text(L("Another Claude account, e.g. work. Log in once in Terminal:", "Outra conta do Claude, ex.: da empresa. Faça login uma vez no Terminal:"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                let _ = store.claude2Dir
                Text(ClaudeAccount.loginCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                link(L("Copy", "Copiar")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ClaudeAccount.loginCommand, forType: .string)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10, content: content).group(padding: 12)
        }
        .padding(.top, 6)
    }

    private func row(_ title: String, detail: String? = nil, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle("", isOn: Binding(get: get, set: set)).softSwitch()
        }
    }

    private func labeledSwitch(_ title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Toggle("", isOn: Binding(get: get, set: set)).softSwitch()
        }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.accent)
    }
}
