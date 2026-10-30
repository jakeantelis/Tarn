import SwiftUI

/// Capsule shaped segmented control with a sliding highlight.
struct PillPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let title: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Text(title(item))
                    .font(.callout.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.75))
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if on { Capsule().fill(.tint).matchedGeometryEffect(id: "pill", in: ns) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = item } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }
}

/// Fully rounded button. Prominent fills with the accent color.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.medium) : .callout)
            .padding(.horizontal, large ? 26 : 14)
            .padding(.vertical, large ? 9 : 6)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background { if prominent { Capsule().fill(.tint) } else { Capsule().fill(Color.secondary.opacity(0.18)) } }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Round icon button.
struct CircleButtonStyle: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .frame(width: 28, height: 28)
            .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
            .background { if on { Circle().fill(.tint) } else { Circle().fill(Color.secondary.opacity(0.18)) } }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A focus lens. The aperture tightens as the round runs out, and a slow steady pulse breathes through it.
struct LensView: View {
    let progress: Double
    let running: Bool

    var body: some View {
        TimelineView(.animation(paused: !running)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = running ? 0.5 + 0.5 * sin(t * 2 * .pi / 3 - .pi / 2) : 0.3
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let base = min(size.width, size.height) / 2
                let f = max(0, min(1, 1 - progress))          // time left
                let green = Color(red: 0.50, green: 0.76, blue: 0.46)
                let amber = Color(red: 0.98, green: 0.80, blue: 0.48)
                func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }

                // time left, as an arc on the outer rim
                var arc = Path()
                arc.addArc(center: c, radius: base - 4, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * f), clockwise: false)
                g.stroke(circle(base - 4), with: .color(green.opacity(0.12)), lineWidth: 3)
                g.stroke(arc, with: .color(green.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // aperture rings tighten with the time left
                let aperture = base * (0.40 + 0.52 * f) * (1 + 0.025 * pulse)
                for (i, k) in [1.0, 0.78, 0.58, 0.40].enumerated() {
                    g.stroke(circle(aperture * k), with: .color(green.opacity(0.42 - 0.08 * Double(i))), lineWidth: 1.2)
                }
                // soft glow at the center
                let core = aperture * (0.36 + 0.06 * pulse)
                g.fill(circle(core), with: .radialGradient(
                    Gradient(colors: [amber.opacity(0.30 + 0.14 * pulse), green.opacity(0.08), green.opacity(0)]),
                    center: c, startRadius: 0, endRadius: core))
                // focus ticks
                for k in 0..<4 {
                    let a = Double(k) * .pi / 2
                    var tick = Path()
                    tick.move(to: CGPoint(x: c.x + cos(a) * (aperture + 3), y: c.y + sin(a) * (aperture + 3)))
                    tick.addLine(to: CGPoint(x: c.x + cos(a) * (aperture + 9), y: c.y + sin(a) * (aperture + 9)))
                    g.stroke(tick, with: .color(green.opacity(0.6)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
        }
    }
}
