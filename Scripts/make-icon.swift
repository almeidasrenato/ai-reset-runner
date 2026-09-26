// Renders Resources/AppIcon.icns: a warm ivory squircle with a sage "reset"
// arc ending in an arrowhead, around a small sage dot.
// Run: swift Scripts/make-icon.swift  (needs only the Command Line Tools)
import AppKit

let sage = NSColor(srgbRed: 0.30, green: 0.46, blue: 0.35, alpha: 1) // #4C7658

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle on Apple's 824pt content grid.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.96, blue: 0.92, alpha: 1),
               ending: NSColor(srgbRed: 0.92, green: 0.89, blue: 0.83, alpha: 1))!.draw(in: body, angle: -90)

    let center = CGPoint(x: 512, y: 512), radius: CGFloat = 250, width: CGFloat = 56
    // Track.
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor(srgbRed: 0.30, green: 0.27, blue: 0.22, alpha: 0.08).setStroke()
    track.stroke()

    // Arc: from the top, clockwise 290°.
    let sweep: CGFloat = 290
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - sweep, clockwise: true)
    arc.lineWidth = width
    arc.lineCapStyle = .round
    sage.setStroke()
    arc.stroke()
    // Arrowhead at the end of the arc, pointing along the clockwise direction.
    let end = (90 - sweep) * .pi / 180
    let tip = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
    let tangent = CGPoint(x: sin(end), y: -cos(end)), normal = CGPoint(x: cos(end), y: sin(end))
    let head = NSBezierPath()
    head.move(to: CGPoint(x: tip.x + tangent.x * 100, y: tip.y + tangent.y * 100))
    head.line(to: CGPoint(x: tip.x + normal.x * 58, y: tip.y + normal.y * 58))
    head.line(to: CGPoint(x: tip.x - normal.x * 58, y: tip.y - normal.y * 58))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 16
    sage.setFill()
    sage.setStroke()
    head.fill()
    head.stroke()

    // Center dot.
    NSBezierPath(ovalIn: NSRect(x: 512 - 44, y: 512 - 44, width: 88, height: 88)).fill()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try! render(1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
