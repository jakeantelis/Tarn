import SwiftUI

enum BreathStyle: String, CaseIterable, Identifiable {
    case fill = "Fill", bloom = "Bloom", rings = "Rings"
    var id: String { rawValue }
}

struct BreathPattern: Identifiable, Hashable {
    let id: String
    let name: String
    /// inhale, hold, exhale, hold (seconds)
    let steps: [Double]

    static let calm = BreathPattern(id: "calm", name: "Calm", steps: [4, 0, 6, 0])
    static let box = BreathPattern(id: "box", name: "Box", steps: [4, 4, 4, 4])
    static let fourSevenEight = BreathPattern(id: "478", name: "4 7 8", steps: [4, 7, 8, 0])
    static let all = [calm, box, fourSevenEight]

    var cycle: Double { steps.reduce(0, +) }

    /// Returns label and circle scale (0...1) at time t into the cycle.
    func state(at t: Double) -> (label: String, scale: Double) {
        let labels = ["Breathe in", "Hold", "Breathe out", "Hold"]
        var t = t.truncatingRemainder(dividingBy: cycle)
        var level = 0.0
        for (i, d) in steps.enumerated() where d > 0 {
            let target: Double
            switch i {
            case 0: target = 1
            case 2: target = 0
            default: target = level
            }
            if t < d {
                let f = t / d
                let eased = (1 - cos(f * .pi)) / 2
                let s = (i == 0 || i == 2) ? level + (target - level) * eased : level
                return (labels[i], s)
            }
            t -= d
            level = target
        }
        return ("Breathe in", 0)
    }
}

struct BreathingView: View {
    var compact = false
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.fill.rawValue
    @State private var pattern = BreathPattern.calm
    @State private var start = Date()

    var body: some View {
        content
            .onAppear { VoiceGuide.shared.reset() }
            .onDisappear { VoiceGuide.shared.reset() }
    }

    private var content: some View {
        VStack(spacing: 12) {
            if !compact {
                Picker("", selection: $pattern) {
                    ForEach(BreathPattern.all) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: pattern) { _, _ in start = Date() }
                Picker("", selection: $styleRaw) {
                    ForEach(BreathStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    BreatheOverlay.shared.show()
                } label: {
                    Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }

            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                let s = pattern.state(at: t)
                ZStack {
                    switch BreathStyle(rawValue: styleRaw) ?? .fill {
                    case .fill: FillCanvas(scale: s.scale, time: t)
                    case .bloom: BloomCanvas(scale: s.scale, time: t)
                    case .rings: RingsCanvas(scale: s.scale, time: t)
                    }
                    Text(s.label)
                        .font(.system(.title3, design: .rounded).weight(.light))
                        .foregroundStyle(.primary.opacity(0.85))
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 160 : 230)
                .onChange(of: s.label) { _, new in VoiceGuide.shared.cue(new) }
            }
        }
    }
}

/// Matcha green bloom: soft petals open on the inhale and close on the exhale.
struct BloomCanvas: View {
    let scale: Double
    let time: Double

    private let greens: [Color] = [
        Color(red: 0.62, green: 0.78, blue: 0.45),
        Color(red: 0.45, green: 0.65, blue: 0.38),
        Color(red: 0.30, green: 0.50, blue: 0.30),
    ]

    var body: some View {
        Canvas { g, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) / 2
            // outer glow
            let glowR = base * (0.55 + 0.4 * scale)
            g.fill(Path(ellipseIn: CGRect(x: c.x - glowR, y: c.y - glowR, width: glowR * 2, height: glowR * 2)),
                   with: .radialGradient(Gradient(colors: [greens[0].opacity(0.35), greens[0].opacity(0)]),
                                         center: c, startRadius: 0, endRadius: glowR))
            // three petal rings, each rotating at a different slow speed
            for (ring, color) in greens.enumerated() {
                let petals = 6 + ring * 2
                let spin = time * (0.04 + 0.025 * Double(ring)) * (ring % 2 == 0 ? 1 : -1)
                let petalR = base * (0.16 + 0.10 * Double(2 - ring) * 0.5) * (0.7 + 0.5 * scale)
                let orbit = base * (0.10 + (0.22 + 0.10 * Double(ring)) * scale)
                for k in 0..<petals {
                    let a = spin + Double(k) / Double(petals) * 2 * .pi
                    let p = CGPoint(x: c.x + cos(a) * orbit, y: c.y + sin(a) * orbit)
                    let r = petalR * (1.0 + 0.6 * scale)
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    g.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.16 + 0.06 * Double(ring))))
                    g.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.35)), lineWidth: 0.8)
                }
            }
            // heart of the bloom
            let hr = base * (0.14 + 0.10 * scale)
            g.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)),
                   with: .radialGradient(Gradient(colors: [greens[0].opacity(0.9), greens[1].opacity(0.25)]),
                                         center: c, startRadius: 0, endRadius: hr))
        }
    }
}

/// Round vessel; water rises on the inhale and drains on the exhale.
struct FillCanvas: View {
    let scale: Double
    let time: Double

    var body: some View {
        Canvas { g, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 8
            let vessel = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let level = c.y + r - (2 * r) * (0.08 + 0.84 * scale)
            g.drawLayer { l in
                l.clip(to: vessel)
                for (i, alpha) in [0.30, 0.45].enumerated() {
                    var wave = Path()
                    let phase = time * (0.9 + 0.4 * Double(i)) + Double(i) * 1.7
                    wave.move(to: CGPoint(x: c.x - r, y: c.y + r))
                    var x = c.x - r
                    while x <= c.x + r {
                        let y = level + sin((x / 22) + phase) * (3.0 + Double(i)) 
                        wave.addLine(to: CGPoint(x: x, y: y))
                        x += 3
                    }
                    wave.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
                    wave.closeSubpath()
                    l.fill(wave, with: .linearGradient(
                        Gradient(colors: [Color.teal.opacity(alpha), Color.blue.opacity(alpha + 0.15)]),
                        startPoint: CGPoint(x: c.x, y: level), endPoint: CGPoint(x: c.x, y: c.y + r)))
                }
            }
            g.stroke(vessel, with: .color(Color.teal.opacity(0.55)), lineWidth: 2)
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.85, width: r * 0.5, height: r * 0.22)),
                   with: .color(.white.opacity(0.10)))
        }
    }
}

/// Glowing orb with ripples that travel outward as you breathe.
struct RingsCanvas: View {
    let scale: Double
    let time: Double

    var body: some View {
        Canvas { g, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) / 2
            for k in 0..<4 {
                let f = (time * 0.15 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
                let rr = base * (0.35 + 0.65 * f) * (0.75 + 0.25 * scale)
                g.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                         with: .color(Color.indigo.opacity(0.35 * (1 - f))), lineWidth: 1.5)
            }
            let orb = base * (0.22 + 0.22 * scale)
            g.fill(Path(ellipseIn: CGRect(x: c.x - orb, y: c.y - orb, width: orb * 2, height: orb * 2)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), Color.indigo.opacity(0.5), Color.indigo.opacity(0.05)]),
                                         center: c, startRadius: 0, endRadius: orb))
        }
    }
}
