import AppKit
import Observation

/// Checks GitHub Releases for a newer version and installs it in place.
/// The release must carry an `AIResetRunner.zip` asset (see `make release`).
@MainActor @Observable
final class Updater {
    static let repo = "almeidasrenato/ai-reset-runner"
    static let repoURL = URL(string: "https://github.com/\(repo)")!
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    var autoCheck = UserDefaults.standard.object(forKey: "update.autoCheck") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "update.autoCheck") }
    }
    var autoInstall = UserDefaults.standard.bool(forKey: "update.autoInstall") {
        didSet { UserDefaults.standard.set(autoInstall, forKey: "update.autoInstall") }
    }
    /// Newer release found, if any.
    var available: (version: String, zip: URL)?
    var status: String?
    var isBusy = false
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.scheduledCheck() }
        }
        Task { await scheduledCheck() }
    }

    private func scheduledCheck() async {
        guard autoCheck else { return }
        await check()
        if available != nil, autoInstall { await install() }
    }

    func check() async {
        isBusy = true
        defer { isBusy = false }
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let assets: [Asset]
        }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                available = nil
                status = L("No version published yet", "Nenhuma versão publicada ainda")
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard Self.isNewer(version, than: Self.current),
                  let zip = release.assets.first(where: { $0.name == "AIResetRunner.zip" })?.browser_download_url
            else {
                available = nil
                status = L("You are on the latest version", "Você está na versão mais recente")
                return
            }
            if available?.version != version {
                notify(L("AI ResetRunner \(version) available", "AI ResetRunner \(version) disponível"), L("Open Settings to update.", "Abra Configurações para atualizar."), kind: .update)
            }
            available = (version, zip)
            status = L("Version \(version) available", "Versão \(version) disponível")
        } catch {
            status = L("Could not check: \(error.localizedDescription)", "Não foi possível verificar: \(error.localizedDescription)")
            log.error("update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Download, unzip, check the bundle id, then swap the app after we quit and relaunch it.
    func install() async {
        guard let available else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let target = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UsageError.badResponse(L("no write permission in \(target.deletingLastPathComponent().path)", "sem permissão para escrever em \(target.deletingLastPathComponent().path)"))
            }
            status = L("Downloading \(available.version)…", "Baixando \(available.version)…")
            let (zip, _) = try await URLSession.shared.download(from: available.zip)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
            let newApp = dir.appendingPathComponent("AIResetRunner.app")
            guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UsageError.badResponse(L("downloaded package is not AI ResetRunner", "pacote baixado não é o AI ResetRunner"))
            }
            let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            rm -rf "$3" && mv "$2" "$3" && xattr -dr com.apple.quarantine "$3" 2>/dev/null; open "$3"
            """
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/sh")
            swap.arguments = ["-c", script, "sh", "\(getpid())", newApp.path, target.path]
            try swap.run()
            log.notice("installing update \(available.version, privacy: .public), relaunching")
            NSApp.terminate(nil)
        } catch {
            status = "Falha ao atualizar: \(error.localizedDescription)"
            log.error("update install failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UsageError.badResponse(L("\(path) exited with \(p.terminationStatus)", "\(path) saiu com \(p.terminationStatus)")) }
    }

    /// Numeric dotted compare: 0.10.0 > 0.9.1.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}
