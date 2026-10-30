import AppKit

// Renders the Stillwater app icon: a midnight tile with a glowing lens of still rings
// and a warm core, a nod to focus (the lens) and breathing (the ripples).
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let tileRect = NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: s*0.215, yRadius: s*0.215)

    // shadow under the tile
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s*0.012), blur: s*0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); tile.fill()
    ctx.restoreGState()

    // background
    tile.addClip()
    NSGradient(colors: [NSColor(red: 0.20, green: 0.27, blue: 0.52, alpha: 1),
                        NSColor(red: 0.07, green: 0.10, blue: 0.24, alpha: 1)])!.draw(in: tileRect, angle: -90)
    let c = NSPoint(x: s/2, y: s/2)

    // soft light behind the lens
    NSGradient(colors: [NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.38), NSColor.clear])!
        .draw(fromCenter: c, radius: 0, toCenter: c, radius: s*0.46, options: [])

    // rings, fading outward, with a bright arc on the outer one
    for (i, r) in [0.34, 0.255, 0.175].enumerated() {
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - s*r, y: c.y - s*r, width: s*r*2, height: s*r*2))
        ring.lineWidth = s * (i == 0 ? 0.022 : 0.014)
        NSColor.white.withAlphaComponent(i == 0 ? 0.30 : 0.22 - 0.05 * CGFloat(i)).setStroke()
        ring.stroke()
    }
    // progress arc on the outer ring: blue into warm coral
    let arcR = s * 0.34
    let steps = 90
    for k in 0..<steps {
        let t = CGFloat(k) / CGFloat(steps)
        let a0 = 90 - t * 250, a1 = 90 - (t + 1.0 / CGFloat(steps)) * 250
        let seg = NSBezierPath()
        seg.appendArc(withCenter: c, radius: arcR, startAngle: a0, endAngle: a1 - 0.6, clockwise: true)
        seg.lineWidth = s * 0.03
        seg.lineCapStyle = .round
        let col = NSColor(red: 0.45 + 0.55 * t, green: 0.75 - 0.30 * t, blue: 1.0 - 0.60 * t, alpha: 1)
        col.setStroke(); seg.stroke()
    }
    // glowing core
    NSGradient(colors: [NSColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 1),
                        NSColor(red: 1.0, green: 0.68, blue: 0.50, alpha: 0.85),
                        NSColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 0)])!
        .draw(fromCenter: c, radius: 0, toCenter: c, radius: s*0.15, options: [])
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - s*0.03, y: c.y - s*0.03, width: s*0.06, height: s*0.06)).fill()

    // glass highlight on the top of the tile
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.13), NSColor.white.withAlphaComponent(0)])!.draw(in: tileRect, angle: -90)

    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
let set = "\(dir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(set)/icon_\(name).png"))
}
