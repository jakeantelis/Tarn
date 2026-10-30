import SwiftUI
import AppKit

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
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.callout.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.onTint : Color.primary.opacity(0.75))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if on { Capsule().fill(.tint).matchedGeometryEffect(id: "pill", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
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
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .font(large ? .title3.weight(.medium) : (small ? .caption : .callout))
            .padding(.horizontal, large ? 26 : (small ? 10 : 14))
            .padding(.vertical, large ? 9 : (small ? 5 : 6))
            .foregroundStyle(prominent ? Color.onTint : Color.primary)
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
            .foregroundStyle(on ? Color.onTint : Color.primary.opacity(0.8))
            .background { if on { Circle().fill(.tint) } else { Circle().fill(Color.secondary.opacity(0.18)) } }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A focus lens. The aperture tightens as the round runs out, and a slow steady pulse breathes through it.
struct LensView: View {
    let progress: Double
    let running: Bool
    @Environment(\.popoverActive) private var active

    var body: some View {
        ZStack {
            // deeper tinted disc while a round is running, only inside the lens
            Circle()
                .fill(RadialGradient(colors: [FocusPalette.current.tint.opacity(0.34), FocusPalette.current.tint.opacity(0.14)],
                                     center: .center, startRadius: 0, endRadius: 100))
                .padding(10)
                .opacity(running ? 1 : 0)
                .animation(.easeInOut(duration: 1.2), value: running)
            lens
        }
    }

    private var lens: some View {
        TimelineView(.animation(paused: !running || !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = running ? 0.5 + 0.5 * sin(t * 2 * .pi / 3 - .pi / 2) : 0.3
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let base = min(size.width, size.height) / 2
                let f = max(0, min(1, 1 - progress))          // time left
                let green = FocusPalette.current.tint
                let amber = FocusPalette.current.glow
                func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }

                // time left, as an arc on the outer rim
                var arc = Path()
                arc.addArc(center: c, radius: base - 4, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * f), clockwise: false)
                g.stroke(circle(base - 4), with: .color(green.opacity(0.12)), lineWidth: 3)
                g.stroke(arc, with: .color(green.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // A soft glowing disc that gently narrows as the round runs out. No target rings or crosshair.
                let disc = base * (0.34 + 0.50 * f) * (1 + 0.03 * pulse)
                g.fill(circle(disc), with: .radialGradient(
                    Gradient(colors: [amber.opacity(0.34 + 0.10 * pulse), green.opacity(0.18), green.opacity(0.0)]),
                    center: c, startRadius: 0, endRadius: disc))
                g.stroke(circle(disc * 0.97), with: .color(green.opacity(0.22)), lineWidth: 1)
            }
        }
    }
}

/// True while the menu bar popover is actually on screen. Animations pause when it is not, so Tarn
/// uses almost no CPU while you work in other apps.
private struct PopoverActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var popoverActive: Bool {
        get { self[PopoverActiveKey.self] }
        set { self[PopoverActiveKey.self] = newValue }
    }
}

struct PopoverVisibilityReader: NSViewRepresentable {
    @Binding var active: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.binding = $active
        if context.coordinator.window == nil {
            DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $active) }

    final class Coordinator {
        var binding: Binding<Bool>
        weak var window: NSWindow?
        private var observer: NSObjectProtocol?
        init(binding: Binding<Bool>) { self.binding = binding }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                self?.refresh()
            }
            refresh()
        }

        private func refresh() {
            guard let window else { return }
            let visible = window.occlusionState.contains(.visible) && window.isVisible
            if binding.wrappedValue != visible { binding.wrappedValue = visible }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
