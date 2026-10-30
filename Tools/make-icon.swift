import AppKit

// Renders the Stillwater app icon: a calm green gradient tile with a water drop and ripples.
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let tile = NSBezierPath(roundedRect: NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88), xRadius: s*0.2, yRadius: s*0.2)
    NSGradient(colors: [NSColor(red: 0.78, green: 0.90, blue: 0.62, alpha: 1), NSColor(red: 0.28, green: 0.52, blue: 0.40, alpha: 1)])!
        .draw(in: tile, angle: -90)
    NSColor.white.withAlphaComponent(0.45).setStroke()
    for (i, r) in [0.33, 0.24, 0.15].enumerated() {
        let p = NSBezierPath(ovalIn: NSRect(x: s/2 - s*r, y: s*0.44 - s*r*0.55, width: s*r*2, height: s*r*1.1))
        p.lineWidth = s * 0.012
        NSColor.white.withAlphaComponent(0.5 - 0.1 * CGFloat(i)).setStroke()
        p.stroke()
    }
    let drop = NSBezierPath()
    drop.move(to: NSPoint(x: s*0.5, y: s*0.78))
    drop.curve(to: NSPoint(x: s*0.5, y: s*0.42), controlPoint1: NSPoint(x: s*0.68, y: s*0.58), controlPoint2: NSPoint(x: s*0.66, y: s*0.42))
    drop.curve(to: NSPoint(x: s*0.5, y: s*0.78), controlPoint1: NSPoint(x: s*0.34, y: s*0.42), controlPoint2: NSPoint(x: s*0.32, y: s*0.58))
    NSColor.white.withAlphaComponent(0.95).setFill()
    drop.fill()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
let set = "\(dir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (n, px) in [("16",16),("16@2x",32),("32",32),("32@2x",64),("128",128),("128@2x",256),("256",256),("256@2x",512),("512",512),("512@2x",1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(set)/icon_\(n.replacingOccurrences(of: "@2x", with: ""))\(n.contains("@2x") ? "@2x" : "").png".replacingOccurrences(of: "icon_\(n.replacingOccurrences(of: "@2x", with: ""))", with: "icon_\(n.replacingOccurrences(of: "@2x", with: ""))x\(n.replacingOccurrences(of: "@2x", with: ""))")))
}
