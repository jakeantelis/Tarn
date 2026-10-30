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

    // faint outer ring, a nod to the focus lens
    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - s*0.385, y: c.y - s*0.385, width: s*0.77, height: s*0.77))
    ring.lineWidth = s * 0.012
    NSColor.white.withAlphaComponent(0.16).setStroke(); ring.stroke()

    // the breathing flower: three rings of translucent petals
    func petals(count: Int, orbit: CGFloat, length: CGFloat, width: CGFloat, turn: CGFloat, color: NSColor) {
        for k in 0..<count {
            let a = turn + CGFloat(k) / CGFloat(count) * 2 * .pi
            let p = NSBezierPath(ovalIn: NSRect(x: -width, y: -length, width: width * 2, height: length * 2))
            var t = AffineTransform(translationByX: c.x + cos(a) * orbit, byY: c.y + sin(a) * orbit)
            t.rotate(byRadians: a - .pi / 2)
            p.transform(using: t)
            color.withAlphaComponent(0.26).setFill(); p.fill()
            color.withAlphaComponent(0.55).setStroke(); p.lineWidth = s * 0.004; p.stroke()
        }
    }
    petals(count: 8, orbit: s*0.155, length: s*0.15, width: s*0.068, turn: 0.0,
           color: NSColor(red: 0.62, green: 0.78, blue: 1.0, alpha: 1))
    petals(count: 8, orbit: s*0.11, length: s*0.115, width: s*0.06, turn: .pi / 8,
           color: NSColor(red: 0.98, green: 0.72, blue: 0.82, alpha: 1))
    petals(count: 6, orbit: s*0.065, length: s*0.08, width: s*0.045, turn: .pi / 6,
           color: NSColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1))

    // glowing core
    NSGradient(colors: [NSColor(red: 1.0, green: 0.95, blue: 0.84, alpha: 1),
                        NSColor(red: 1.0, green: 0.75, blue: 0.55, alpha: 0.7),
                        NSColor(red: 1.0, green: 0.6, blue: 0.5, alpha: 0)])!
        .draw(fromCenter: c, radius: 0, toCenter: c, radius: s*0.11, options: [])

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
