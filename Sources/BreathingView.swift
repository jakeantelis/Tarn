import SwiftUI

enum BreathStyle: String, CaseIterable, Identifiable {
    case bloom = "Flower", fill = "Water"
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

    var blurb: String {
        switch id {
        case "settle": return "Starts easy and slowly deepens over three minutes. A good everyday choice."
        case "deep": return "In for 6, a short pause, out for 8. A slow, full breath."
        case "box": return "In for 4, hold 4, out for 4, hold 4. Steady and even."
        default: return "In for 4, hold for 7, out for 8. Good for winding down."
        }
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
    /// Holds the picture still, half open, with a quiet label. Used before a break has started.
    var still = false
    /// Opens the full sound mixer. Provided by the Breathe screen.
    var onMix: (() -> Void)? = nil
    @Environment(\.popoverActive) private var active
    @Environment(\.chromeVisible) private var chrome
    @State private var blurbShown = false
    @AppStorage("guideMe") private var guideMe = false
    @ObservedObject private var cleared = ScreenClearer.shared
    @ObservedObject private var sound = AppModel.shared.sound
    @AppStorage("allowScreenTakeover") private var allowTakeover = true
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.bloom.rawValue
    @AppStorage("breathPattern") private var patternID = "settle"
    private var pattern: BreathPattern {
        get { BreathPattern.all.first { $0.id == patternID } ?? .settle }
        nonmutating set { patternID = newValue.id }
    }
    @State private var start = Date()
    @State private var pausedAt: TimeInterval? = nil   // elapsed seconds while paused
    @AppStorage("coachMinutes") private var coachMinutes = 0
    @State private var coachStart: Date? = nil
    @State private var coachDone = false
    @State private var burst = 0
    @State private var pausedFrom: Date? = nil
    @State private var soundWasOn = false

    var body: some View {
        content
            .background(compact ? nil : RoundedRectangle(cornerRadius: 34)
                .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.40, blue: 0.62).opacity(0.22),
                                              Color(red: 0.25, green: 0.55, blue: 0.58).opacity(0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(-8))
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in checkCoach() }
            .onAppear { if coachMinutes > 0 && coachStart == nil && !compact { coachMinutes = 0 } }
    }

    /// One quiet menu for the things you set once: session length, the look, and background sound.
    private var optionsMenu: some View {
        Menu {
            Section("Session") {
                ForEach([0, 1, 3, 5, 10, 20], id: \.self) { m in
                    Button { setCoach(m) } label: {
                        let name = m == 0 ? "No timer" : "\(m) minutes"
                        if coachMinutes == m { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            }
            Section("Rhythm") {
                ForEach(BreathPattern.all) { pt in
                    Button {
                        pattern = pt; start = Date()
                    } label: {
                        if patternID == pt.id { Label(pt.name, systemImage: "checkmark") } else { Text(pt.name) }
                    }
                }
            }
            Section("Look") {
                ForEach(BreathStyle.allCases) { st in
                    Button { withAnimation(.easeInOut(duration: 0.4)) { styleRaw = st.rawValue } } label: {
                        if styleRaw == st.rawValue { Label(st.rawValue, systemImage: "checkmark") } else { Text(st.rawValue) }
                    }
                }
            }
            Section("Sound") {
                ForEach(SoundPreset.all) { p in
                    Button { sound.applyPreset(p) } label: { Label(p.name, systemImage: p.symbol) }
                }
                Button("Sound off") { sound.stop() }
                if let onMix { Button("Mix sounds…") { onMix() } }
            }
            Section("More") {
                if allowTakeover {
                    Button("Full screen") { BreatheOverlay.shared.show() }
                    Button(cleared.isCleared ? "Bring back hidden apps" : "Hide other apps") { cleared.isCleared ? cleared.restore() : cleared.clear() }
                }
                Button { guideMe.toggle() } label: {
                    if guideMe { Label("Gentle guide", systemImage: "checkmark") } else { Text("Gentle guide") }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                Text(coachMinutes == 0 ? "Options" : "\(coachMinutes) min session")
                if sound.isPlaying { Image(systemName: "speaker.wave.2.fill").font(.system(size: 9)) }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Session length, rhythm, look, sound and screen")
    }

    private func setCoach(_ minutes: Int) {
        coachMinutes = minutes
        coachDone = false
        start = Date(); pausedAt = nil
        coachStart = minutes > 0 ? Date() : nil
        if minutes > 0 {
            burst += 1
            AppModel.shared.startBreatheSound()
        }
    }

    private func checkCoach() {
        guard let cs = coachStart, coachMinutes > 0 else { return }
        let elapsed = Date().timeIntervalSince(cs), total = Double(coachMinutes * 60)
        guard elapsed >= total else { return }
        coachStart = nil
        coachDone = true
        // The ambient sound fading out is the signal that the session is over, unless the user keeps it on.
        if !UserDefaults.standard.bool(forKey: "keepSoundAfterSession") { AppModel.shared.sound.stop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { coachDone = false }
    }

    private var content: some View {
        VStack(spacing: 12) {
            if !compact {
                HStack(spacing: 8) {
                    optionsMenu
                    if allowTakeover {
                        Button { BreatheOverlay.shared.show() } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(7)
                                .background(Circle().fill(Color.secondary.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .help("Full screen. Esc or a click brings you back.")
                        .accessibilityLabel("Full screen")
                    }
                }
                .fadesWithChrome(chrome)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active || pausedAt != nil || still)) { ctx in
                let t = still ? 2.0 : (pausedAt ?? ctx.date.timeIntervalSince(start))
                let s = pattern.state(at: t)
                VStack(spacing: 8) {
                ZStack {
                    RippleBurst(color: Color.breatheTint, trigger: burst).padding(10)
                    switch BreathStyle(rawValue: styleRaw) ?? .bloom {
                    case .fill: FillCanvas(scale: s.scale, time: t)
                    case .bloom: BloomCanvas(scale: s.scale, time: t)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 120 : 190)
                // With the controls out of the way, the picture grows to fill the card.
                .scaleEffect(!compact && !still && !chrome ? 1.3 : 1)
                .animation(.easeInOut(duration: 0.9), value: chrome)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !compact else { return }
                    if let p = pausedAt {
                        // Resume: the breath, the session clock and the sound all pick up where they stopped.
                        start = Date().addingTimeInterval(-p)
                        if let at = pausedFrom, coachStart != nil { coachStart = coachStart?.addingTimeInterval(Date().timeIntervalSince(at)) }
                        pausedAt = nil; pausedFrom = nil
                        if soundWasOn { soundWasOn = false; sound.play() }
                    } else {
                        // Pause: the sound stops too, so a paused session is really quiet.
                        pausedAt = Date().timeIntervalSince(start); pausedFrom = Date()
                        soundWasOn = sound.isPlaying
                        if soundWasOn { sound.stop() }
                    }
                }
                .help(compact ? "" : (pausedAt == nil ? "Click to pause" : "Click to resume"))

                // The cue sits under the picture, not on top of it, so it is always easy to read.
                // A soft, lowercase cue that fades from one word to the next.
                Text((still ? "when you are ready" : (pausedAt != nil ? "Paused. Tap to resume" : s.label)).lowercased())
                    .font(.system(size: compact ? 17 : 21, weight: .light, design: .serif))
                    .tracking(1.6)
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(height: 28)
                    .id(still ? "still" : (pausedAt != nil ? "paused" : s.label))
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.9), value: s.label)
                if let cs = coachStart, coachMinutes > 0 {
                    let left = max(0, Double(coachMinutes * 60) - ctx.date.timeIntervalSince(cs))
                    Text(String(format: "%d:%02d left", Int(left) / 60, Int(left) % 60))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if sound.isPlaying {
                        Text("Sound is on. Change it in Options, or turn it off in Settings.")
                            .font(.caption2).foregroundStyle(.secondary.opacity(0.8)).multilineTextAlignment(.center)
                    }
                } else if coachDone {
                    Text("Well done. Take a moment before you go.").font(.caption).foregroundStyle(.secondary)
                }
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
            }

            if !compact {
                if allowTakeover {
                    Button { AppModel.shared.calmMode() } label: {
                        Label("Calm mode", systemImage: "moon.stars").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, small: true))
                    .help("Full screen, your sound mix and Hide apps in one go. Esc or a click brings you back.")
                    .fadesWithChrome(chrome)
                }
            }
        }
    }
}

/// Flower bloom: soft petals open on the inhale and close on the exhale.
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
                let spin = (reduceMotion ? 0 : time) * (0.04 + 0.025 * Double(ring)) * (ring % 2 == 0 ? 1 : -1)
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
