// Draws the AgentBuddy app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
import AppKit

/// One robot: rounded body, two legs, eyes, a smile; optionally a raised, waving arm on its left.
func robot(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: NSColor, s: CGFloat, wave: Bool) {
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    color.setFill()
    if wave {   // arm: a rounded bar tilted up and out from the upper-left of the body, with a round hand
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: (x + 28) * s, y: (y + 150) * s)
        ctx.rotate(by: .pi / 4)
        NSBezierPath(roundedRect: NSRect(x: -150 * s, y: -26 * s, width: 170 * s, height: 52 * s), xRadius: 26 * s, yRadius: 26 * s).fill()
        NSBezierPath(ovalIn: NSRect(x: -186 * s, y: -40 * s, width: 80 * s, height: 80 * s)).fill()
        ctx.restoreGState()
    }
    NSBezierPath(roundedRect: r(x, y, w, h), xRadius: w * 0.21 * s, yRadius: w * 0.21 * s).fill()
    let legW = w * 0.165, legH = h * 0.33
    NSBezierPath(roundedRect: r(x + w * 0.2, y + h - 10, legW, legH), xRadius: legW * 0.35 * s, yRadius: legW * 0.35 * s).fill()
    NSBezierPath(roundedRect: r(x + w * 0.8 - legW, y + h - 10, legW, legH), xRadius: legW * 0.35 * s, yRadius: legW * 0.35 * s).fill()

    let ink = NSColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1)
    ink.setFill()
    let eyeW = w * 0.14, eyeH = h * 0.25
    NSBezierPath(roundedRect: r(x + w * 0.27, y + h * 0.28, eyeW, eyeH), xRadius: eyeW * 0.35 * s, yRadius: eyeW * 0.35 * s).fill()
    NSBezierPath(roundedRect: r(x + w * 0.73 - eyeW, y + h * 0.28, eyeW, eyeH), xRadius: eyeW * 0.35 * s, yRadius: eyeW * 0.35 * s).fill()
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: (x + w * 0.35) * s, y: (y + h * 0.7) * s))
    smile.curve(to: NSPoint(x: (x + w * 0.65) * s, y: (y + h * 0.7) * s),
                controlPoint1: NSPoint(x: (x + w * 0.42) * s, y: (y + h * 0.83) * s),
                controlPoint2: NSPoint(x: (x + w * 0.58) * s, y: (y + h * 0.83) * s))
    smile.lineWidth = w * 0.065 * s
    smile.lineCapStyle = .round
    ink.setStroke()
    smile.stroke()
}

func draw(_ size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        let s = size / 1024
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

        // macOS icon grid: 824pt rounded square centred on a 1024 canvas
        let tile = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 24 * s
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.set()
        NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.05, alpha: 1)])!.draw(in: tile, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // notch at the top edge — where the app lives
        NSColor.black.setFill()
        NSBezierPath(roundedRect: r(372, 100, 280, 70), xRadius: 34 * s, yRadius: 34 * s).fill()
        NSBezierPath(rect: r(372, 100, 280, 35)).fill()

        // soft lime glow behind the buddy
        let lime = NSColor(red: 0.84, green: 0.95, blue: 0.29, alpha: 1)
        let c = NSPoint(x: 512 * s, y: 530 * s)
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        NSGradient(colors: [lime.withAlphaComponent(0.30), lime.withAlphaComponent(0)])!
            .draw(fromCenter: c, radius: 0, toCenter: c, radius: 340 * s, options: [])
        NSGraphicsContext.restoreGraphicsState()

        // two buddies: a big lime one waving, a small blue friend beside it
        robot(x: 282, y: 362, w: 350, h: 300, color: lime, s: s, wave: true)
        robot(x: 668, y: 502, w: 190, h: 165, color: NSColor(red: 0.31, green: 0.55, blue: 0.97, alpha: 1), s: s, wave: false)

        // a little "needs you" dot above the friend — the app's one alert colour
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: r(800, 440, 58, 58)).fill()
        return true
    }
}

func png(_ img: NSImage, _ px: Int, height: Int? = nil) -> Data {
    let ph = height ?? px
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: ph, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: ph))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! png(draw(CGFloat(px)), px).write(to: set.appendingPathComponent(name))
    }
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try! png(draw(1024), 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
// README banner: icon + wordmark
let banner = NSImage(size: NSSize(width: 1280, height: 400), flipped: false) { rect in
    NSColor(white: 0.07, alpha: 1).setFill(); rect.fill()
    draw(320).draw(in: NSRect(x: 90, y: 40, width: 320, height: 320))
    let title = NSAttributedString(string: "AgentBuddy", attributes: [
        .font: NSFont.systemFont(ofSize: 110, weight: .heavy), .foregroundColor: NSColor.white])
    title.draw(at: NSPoint(x: 440, y: 190))
    let tag = NSAttributedString(string: "Your Claude Code sessions, in the notch.", attributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .medium),
        .foregroundColor: NSColor(red: 0.84, green: 0.95, blue: 0.29, alpha: 1)])
    tag.draw(at: NSPoint(x: 446, y: 120))
    return true
}
try! fm.createDirectory(atPath: "docs", withIntermediateDirectories: true)
try! png(banner, 1280, height: 400).write(to: URL(fileURLWithPath: "docs/banner.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
