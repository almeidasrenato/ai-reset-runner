// Renders Resources/AppIcon.icns: a graphite squircle with a blue "reset"
// arc ending in an arrowhead, and "AI" in the middle.
// Run: swift Scripts/make-icon.swift  (needs only the Command Line Tools)
import AppKit

func ramp(_ t: CGFloat) -> NSColor { // deep blue #3D7BD9 → light blue #7DBBFF
    NSColor(srgbRed: 0.24 + 0.25 * t, green: 0.48 + 0.25 * t, blue: 0.85 + 0.15 * t, alpha: 1)
}

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
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1),
               ending: NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1))!.draw(in: body, angle: -90)

    let center = CGPoint(x: 512, y: 512), radius: CGFloat = 270, width: CGFloat = 64
    // Track.
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor(white: 1, alpha: 0.08).setStroke()
    track.stroke()

    // Arc: from the top, clockwise 290°, drawn in short segments for the gradient.
    let sweep: CGFloat = 290, steps = 120
    for i in 0..<steps {
        let a0 = 90 - sweep * CGFloat(i) / CGFloat(steps)
        let a1 = 90 - sweep * CGFloat(i + 1) / CGFloat(steps) - 0.6
        let seg = NSBezierPath()
        seg.appendArc(withCenter: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
        seg.lineWidth = width
        seg.lineCapStyle = i == 0 ? .round : .butt
        ramp(CGFloat(i) / CGFloat(steps)).setStroke()
        seg.stroke()
    }
    // Arrowhead at the end of the arc, pointing along the clockwise direction.
    let end = (90 - sweep) * .pi / 180
    let tip = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
    let tangent = CGPoint(x: sin(end), y: -cos(end)), normal = CGPoint(x: cos(end), y: sin(end))
    let head = NSBezierPath()
    head.move(to: CGPoint(x: tip.x + tangent.x * 115, y: tip.y + tangent.y * 115))
    head.line(to: CGPoint(x: tip.x + normal.x * 66, y: tip.y + normal.y * 66))
    head.line(to: CGPoint(x: tip.x - normal.x * 66, y: tip.y - normal.y * 66))
    head.close()
    ramp(1).setFill()
    head.fill()

    // "AI".
    let base = NSFont.systemFont(ofSize: 230, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 230) } ?? base
    let text = NSAttributedString(string: "AI", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = text.size()
    text.draw(at: CGPoint(x: 512 - size.width / 2, y: 512 - size.height / 2 + 8))

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
