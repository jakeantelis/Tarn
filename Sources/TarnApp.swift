import SwiftUI
import AppKit

@main
struct TarnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var timer = AppModel.shared.timer
    @StateObject private var sound = AppModel.shared.sound

    var body: some Scene {
        MenuBarExtra {
            ContentView(timer: timer, sound: sound)
        } label: {
            HStack(spacing: 4) {
                if timer.isRunning || (timer.mode.hasTimer && timer.remaining < timer.duration(for: timer.phase)) {
                    Image(nsImage: Self.ringIcon(progress: timer.progress))
                    if !timer.hideCountdown { Text(timer.clockText).monospacedDigit() }
                } else {
                    Image(nsImage: Self.flowerIcon(open: 0.5))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Menu bar flower: six petals that open and close with `open` (0 to 1). A template, so it follows the menu bar tint.
    /// Images are cached and reused. A fresh NSImage on every body evaluation makes the status item
    /// redraw forever (it was growing memory at about 70 MB a second), so each frame is built once.
    private static var flowerCache: [Int: NSImage] = [:]
    private static var ringCache: [Int: NSImage] = [:]

    static func flowerIcon(open: Double) -> NSImage {
        let key = Int((max(0, min(1, open)) * 12).rounded())
        if let cached = flowerCache[key] { return cached }
        let img = makeFlower(open: Double(key) / 12)
        flowerCache[key] = img
        return img
    }

    private static func ringIcon(progress: Double) -> NSImage {
        let key = Int((max(0, min(1, progress)) * 120).rounded())
        if let cached = ringCache[key] { return cached }
        let img = makeRing(progress: Double(key) / 120)
        ringCache[key] = img
        return img
    }

    /// Draws into a real bitmap (2x) so the menu bar gets a static image, not a drawing handler it re-runs.
    private static func bitmapIcon(size: NSSize, draw: (NSRect) -> Void) -> NSImage {
        let scale = 2
        let px = NSSize(width: size.width * CGFloat(scale), height: size.height * CGFloat(scale))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        img.isTemplate = true
        return img
    }

    private static func makeFlower(open: Double) -> NSImage {
        let img = bitmapIcon(size: NSSize(width: 16, height: 16)) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let o = CGFloat(open)
            NSColor.black.setStroke()
            for k in 0..<6 {
                let a = CGFloat(k) / 6 * 2 * .pi
                let petal = NSBezierPath(ovalIn: NSRect(x: -1.8, y: -(2.9 + 1.0 * o), width: 3.6, height: 2 * (2.9 + 1.0 * o)))
                var t = AffineTransform(translationByX: c.x + cos(a) * (2.4 + 1.55 * o), byY: c.y + sin(a) * (2.4 + 1.55 * o))
                t.rotate(byRadians: a - .pi / 2)
                petal.transform(using: t)
                petal.lineWidth = 1.0
                petal.stroke()
            }
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.3, y: c.y - 1.3, width: 2.6, height: 2.6)).fill()
        }
        return img
    }

    /// Small ring that fills as the round progresses; drawn as a template so it follows the menu bar tint.
    private static func makeRing(progress: Double) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let img = bitmapIcon(size: size) { rect in
            let r = rect.insetBy(dx: 2, dy: 2)
            let track = NSBezierPath(ovalIn: r)
            track.lineWidth = 1.6
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            let c = NSPoint(x: rect.midX, y: rect.midY)
            arc.appendArc(withCenter: c, radius: r.width / 2, startAngle: 90,
                          endAngle: 90 - 360 * CGFloat(max(0.02, progress)), clockwise: true)
            arc.lineWidth = 1.8
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
        }
        return img
    }
}
