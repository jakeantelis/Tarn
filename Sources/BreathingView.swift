import SwiftUI

enum BreathStyle: String, CaseIterable, Identifiable {
    case fill = "Water", bloom = "Flower", rings = "Ripples"
    var id: String { rawValue }
}

struct BreathPattern: Identifiable, Hashable {
    let id: String
    let name: String
    /// inhale, hold, exhale, hold (seconds)
    let steps: [Double]
    /// Gradually slows the breath over a few minutes, the way a guided meditation settles you.
    var settling = false

    static let settle = BreathPattern(id: "settle", name: "Settle", steps: [4, 0, 6, 0], settling: true)
    static let deep = BreathPattern(id: "deep", name: "Deep", steps: [6, 2, 8, 0])
    static let box = BreathPattern(id: "box", name: "Box", steps: [4, 4, 4, 4])
    static let fourSevenEight = BreathPattern(id: "478", name: "4 7 8", steps: [4, 7, 8, 0])
    static let all = [settle, deep, box, fourSevenEight]

    /// Warps elapsed time so the cycle stretches from 1x to 1.7x over three minutes, then holds there.
    func warped(_ t: Double) -> Double {
        guard settling else { return t }
        let k = 0.7 / 180, cap = 180.0
        if t <= cap { return log(1 + k * t) / k }
        return log(1 + k * cap) / k + (t - cap) / 1.7
    }

    var cycle: Double { steps.reduce(0, +) }

    /// Returns label and circle scale (0...1) at time t into the cycle.
    func state(at t: Double) -> (label: String, scale: Double) {
        let labels = ["Breathe in", "Hold", "Breathe out", "Hold"]
        var t = warped(t).truncatingRemainder(dividingBy: cycle)
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
    @Environment(\.popoverActive) private var active
    @AppStorage("guideMe") private var guideMe = false
    @ObservedObject private var cleared = ScreenClearer.shared
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.fill.rawValue
    @State private var pattern = BreathPattern.settle
    @State private var start = Date()
    @State private var pausedAt: TimeInterval? = nil   // elapsed seconds while paused

    var body: some View {
        content
            .background(compact ? nil : RoundedRectangle(cornerRadius: 34)
                .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.40, blue: 0.62).opacity(0.22),
                                              Color(red: 0.25, green: 0.55, blue: 0.58).opacity(0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(-8))
            .onAppear { VoiceGuide.shared.reset() }
            .onDisappear { VoiceGuide.shared.reset() }
    }

    private var content: some View {
        VStack(spacing: 12) {
            if !compact {
                PillPicker(items: BreathPattern.all, selection: $pattern) { $0.name }
                .onChange(of: pattern) { _, _ in start = Date() }
            }

            TimelineView(.animation(paused: !active || pausedAt != nil)) { ctx in
                let t = pausedAt ?? ctx.date.timeIntervalSince(start)
                let s = pattern.state(at: t)
                ZStack {
                    switch BreathStyle(rawValue: styleRaw) ?? .fill {
                    case .fill: FillCanvas(scale: s.scale, time: t)
                    case .bloom: BloomCanvas(scale: s.scale, time: t)
                    case .rings: RingsCanvas(scale: s.scale, time: t)
                    }
                    VStack(spacing: 6) {
                        Spacer()
                        Text(pausedAt != nil ? "Paused" : s.label)
                            .font(.system(.title3, design: .rounded).weight(.light))
                            .foregroundStyle(.primary.opacity(0.85))
                        Spacer()
                        if guideMe && !compact {
                            Text(Guidance.line(at: t))
                                .font(.system(.caption, design: .serif).italic())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(height: 30)
                                .id(Guidance.index(at: t))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 1.2), value: Guidance.index(at: t))
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 160 : 230)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !compact else { return }
                    if let p = pausedAt { start = Date().addingTimeInterval(-p); pausedAt = nil }
                    else { pausedAt = Date().timeIntervalSince(start) }
                }
                .help(compact ? "" : (pausedAt == nil ? "Click to pause" : "Click to resume"))
                .onChange(of: s.label) { _, new in VoiceGuide.shared.cue(new) }
                .onChange(of: Guidance.index(at: t)) { _, _ in if guideMe { VoiceGuide.shared.say(Guidance.line(at: t)) } }
            }

            if !compact {
                HStack(spacing: 6) {
                    Button { BreatheOverlay.shared.show() } label: { Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(CapsuleButtonStyle(small: true))
                        .help("Dim every screen so you can breathe. Esc leaves.")
                    Button { cleared.isCleared ? cleared.restore() : cleared.clear() } label: {
                        Label(cleared.isCleared ? "Bring back" : "Hide apps", systemImage: cleared.isCleared ? "rectangle.on.rectangle" : "rectangle.on.rectangle.slash")
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: cleared.isCleared, small: true))
                    .help("Hides other windows. Nothing is quit.")
                    Button { guideMe.toggle() } label: { Label("Guide", systemImage: "text.bubble") }
                        .buttonStyle(CapsuleButtonStyle(prominent: guideMe, small: true))
                        .help("Gentle prompts while you breathe")
                }
                .font(.caption)
            }
        }
    }
}

/// Matcha green bloom: soft petals open on the inhale and close on the exhale.
struct BloomCanvas: View {
    let scale: Double
    let time: Double

    private let greens: [Color] = [
        Color(red: 0.98, green: 0.80, blue: 0.84),   // outer petals, soft pink
        Color(red: 0.96, green: 0.70, blue: 0.78),
        Color(red: 0.93, green: 0.84, blue: 0.62),   // warm center
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
                let petals = 5 + ring
                let spin = time * (0.04 + 0.025 * Double(ring)) * (ring % 2 == 0 ? 1 : -1)
                let petalR = base * (0.13 - 0.02 * Double(ring)) * (0.7 + 0.5 * scale)
                let orbit = base * (0.06 + (0.20 + 0.08 * Double(ring)) * scale)
                for k in 0..<petals {
                    let a = spin + Double(k) / Double(petals) * 2 * .pi
                    let p = CGPoint(x: c.x + cos(a) * orbit, y: c.y + sin(a) * orbit)
                    let len = petalR * 2.1, wid = petalR * 1.05
                    let petal = Path(ellipseIn: CGRect(x: -wid, y: -len, width: wid * 2, height: len * 2))
                        .applying(CGAffineTransform(rotationAngle: a - .pi / 2).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
                    g.fill(petal, with: .color(color.opacity(0.20 + 0.05 * Double(ring))))
                    g.stroke(petal, with: .color(color.opacity(0.40)), lineWidth: 0.8)
                }
            }
            // heart of the bloom
            let hr = base * (0.14 + 0.10 * scale)
            g.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)),
                   with: .radialGradient(Gradient(colors: [greens[2].opacity(0.95), greens[1].opacity(0.2)]),
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
                        Gradient(colors: [Color(red: 0.62, green: 0.84, blue: 0.84).opacity(alpha), Color(red: 0.42, green: 0.66, blue: 0.80).opacity(alpha + 0.05)]),
                        startPoint: CGPoint(x: c.x, y: level), endPoint: CGPoint(x: c.x, y: c.y + r)))
                }
            }
            g.stroke(vessel, with: .color(Color(red: 0.62, green: 0.84, blue: 0.84).opacity(0.45)), lineWidth: 1.5)
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
                         with: .color(Color(red: 0.62, green: 0.70, blue: 0.90).opacity(0.35 * (1 - f))), lineWidth: 1.5)
            }
            let orb = base * (0.22 + 0.22 * scale)
            g.fill(Path(ellipseIn: CGRect(x: c.x - orb, y: c.y - orb, width: orb * 2, height: orb * 2)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), Color(red: 0.62, green: 0.70, blue: 0.90).opacity(0.5), Color(red: 0.62, green: 0.70, blue: 0.90).opacity(0.05)]),
                                         center: c, startRadius: 0, endRadius: orb))
        }
    }
}
