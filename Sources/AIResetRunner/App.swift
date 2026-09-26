import AppKit
import SwiftUI

@main
struct AIResetRunnerApp: App {
    private let store = Store()

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            if store.shown.isEmpty {
                Image(systemName: "arrow.clockwise.circle")
            } else {
                Image(nsImage: MenuBarIcon.image(sessions: store.shown.map { $0.reading?.session }))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .padding(.horizontal, 20)
                .padding(.top, 34)
                .padding(.bottom, 20)
                .frame(width: 420)
                .background(Theme.background)
                .background(WindowChrome())
                .appStyle()
                .id(store.language)
        }
    }
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
