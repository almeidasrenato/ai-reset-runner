import AppKit
import Observation
import SwiftUI

@main
struct AIResetRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar item and windows are AppKit (see AppDelegate); SwiftUI needs one scene.
    // Its own "Settings…" command (⌘,) would open an empty window, so route it to ours.
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(L("Settings…", "Configurações…")) { delegate.showSettings() }
                        .keyboardShortcut(",")
                }
            }
    }
}

/// Status item + popover instead of MenuBarExtra: a popover stays anchored to
/// the icon when its content changes height (hiding a provider, an error line),
/// while MenuBarExtra's window drifts away from the menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSHostingController(rootView: Panel(store: store, openSettings: { [weak self] in self?.showSettings() }))
        panel.sizingOptions = .preferredContentSize
        popover.contentViewController = panel
        popover.behavior = .transient

        // Newer macOS opens SwiftUI's empty Settings scene on launch and reopen; keep it closed.
        NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, window.isVisible,
                  window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" else { return }
            window.close()
        }

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        updateIcon()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Redraws the rings whenever a reading or the shown providers change.
    private func updateIcon() {
        withObservationTracking {
            let shown = store.shown
            statusItem.button?.image = shown.isEmpty
                ? NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: "AI ResetRunner")
                : MenuBarIcon.image(sessions: shown.map { $0.reading?.session })
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let view = SettingsView(store: store)
                .padding(.horizontal, 20)
                .padding(.top, 34)
                .padding(.bottom, 20)
                .frame(width: 420)
                .appStyle()
            let window = NSWindow(contentViewController: NSHostingController(rootView: LanguageKeyed(store: store) { view }))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Rebuilds its content when the language changes, so every string is re-read.
struct LanguageKeyed<Content: View>: View {
    let store: Store
    @ViewBuilder let content: () -> Content

    var body: some View { content().id(store.language) }
}

/// Two tiny rings, one per provider, filled by 5h session usage. A dotted ring
/// means no active window. Template image, so it follows the menu bar's ink.
enum MenuBarIcon {
    static func image(sessions: [LimitWindow?]) -> NSImage {
        let ring: CGFloat = 13, gap: CGFloat = 4, line: CGFloat = 2.2
        let size = NSSize(width: ring * CGFloat(sessions.count) + gap * CGFloat(sessions.count - 1), height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            for (i, session) in sessions.enumerated() {
                let rect = NSRect(x: CGFloat(i) * (ring + gap), y: (size.height - ring) / 2, width: ring, height: ring)
                    .insetBy(dx: line / 2, dy: line / 2)
                let center = NSPoint(x: rect.midX, y: rect.midY)
                let track = NSBezierPath(ovalIn: rect)
                track.lineWidth = line
                guard let session, !session.isIdle() else {
                    NSColor.black.setStroke()
                    track.setLineDash([1.2, 1.8], count: 2, phase: 0)
                    track.stroke()
                    continue
                }
                NSColor.black.withAlphaComponent(0.3).setStroke()
                track.stroke()
                let fraction = min(max(session.usedPercent / 100, 0.04), 1)
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: rect.width / 2, startAngle: 90,
                              endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = line
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
