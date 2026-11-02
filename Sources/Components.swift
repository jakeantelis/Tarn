import SwiftUI
import AppKit
import UserNotifications

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
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
    @State private var burst = 0

    var body: some View {
        ZStack {
            RippleBurst(color: FocusPalette.current.tint, trigger: burst).padding(2)
            // deeper tinted disc while a round is running, only inside the lens
            Circle()
                .fill(RadialGradient(colors: [FocusPalette.current.tint.opacity(0.34), FocusPalette.current.tint.opacity(0.14)],
                                     center: .center, startRadius: 0, endRadius: 100))
                .padding(10)
                .opacity(running ? 1 : 0)
                .animation(.easeInOut(duration: 1.2), value: running)
            lens
        }
        .onChange(of: running) { _, now in if now { burst += 1 } }
    }

    private var lens: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running || !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = running && !reduceMotion ? 0.5 + 0.5 * sin(t * 2 * .pi / 3 - .pi / 2) : 0.3
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

/// Respect the Mac's Reduce Motion setting: slower, quieter animation.
var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

/// Optional warmer colors in the evening for Breathe.
extension Color {
    static var breatheTint: Color {
        let evening = UserDefaults.standard.bool(forKey: "eveningWarmth")
        let h = Calendar.current.component(.hour, from: Date())
        if evening && (h >= 19 || h < 6) { return Color(red: 0.86, green: 0.60, blue: 0.56) }
        return .water
    }
}

/// Runs a Shortcut by name, quietly. Nothing runs when the name is empty.
func runShortcutNamed(_ name: String) {
    let n = name.trimmingCharacters(in: .whitespaces)
    guard !n.isEmpty else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    task.arguments = ["run", n]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
}

/// A soft, silent banner. Only used if the user turned the reminder on.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
    static func post(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// One slow, soft ring that opens outward and fades, to mark a beginning without any sound or fuss.
struct RippleBurst: View {
    let color: Color
    let trigger: Int
    @State private var open = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.55), lineWidth: 2)
            .scaleEffect(open ? 1.22 : 0.82)
            .opacity(open ? 0 : 1)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { open = false }
                DispatchQueue.main.async { withAnimation(.easeOut(duration: 1.6)) { open = true } }
            }
    }
}

/// While you breathe and the mouse is still, the controls fade so only the picture and the word remain.
private struct ChromeVisibleKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var chromeVisible: Bool {
        get { self[ChromeVisibleKey.self] }
        set { self[ChromeVisibleKey.self] = newValue }
    }
}

extension View {
    /// Fades a control out with the rest of the chrome, and makes it ignore clicks while it is invisible.
    func fadesWithChrome(_ visible: Bool) -> some View {
        self.opacity(visible ? 1 : 0).allowsHitTesting(visible).animation(.easeInOut(duration: 1.2), value: visible)
    }
}

/// Asks for a focus length from 1 to 180 minutes. Returns nil if cancelled.
@MainActor
enum CustomLengthPrompt {
    static func ask(current: Int) -> Int? {
        let alert = NSAlert()
        alert.messageText = "Focus length"
        alert.informativeText = "Any length from 1 to 180 minutes."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        let f = NumberFormatter()
        f.minimum = 1; f.maximum = 180; f.allowsFloats = false
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.formatter = f
        field.integerValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let m = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) ?? current
        return PomodoroTimer.clampMinutes(m)
    }
}
