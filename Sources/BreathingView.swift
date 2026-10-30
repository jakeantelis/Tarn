import SwiftUI

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
    @State private var pattern = BreathPattern.calm
    @State private var start = Date()

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $pattern) {
                ForEach(BreathPattern.all) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: pattern) { _, _ in start = Date() }

            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                let s = pattern.state(at: t)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.teal.opacity(0.55), Color.teal.opacity(0.08)],
                                             center: .center, startRadius: 4, endRadius: 90))
                        .frame(width: 70 + 110 * s.scale, height: 70 + 110 * s.scale)
                    Circle()
                        .strokeBorder(Color.teal.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 70 + 110 * s.scale, height: 70 + 110 * s.scale)
                    Text(s.label)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
    }
}
