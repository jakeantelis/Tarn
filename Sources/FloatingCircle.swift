import SwiftUI
import AppKit

/// An optional small circle that floats above your other windows. It shows the Focus timer, or the
/// breathing picture while you are in Breathe. Off by default, and it never takes focus from what you are doing.
@MainActor
final class FloatingCircle {
    static let shared = FloatingCircle()
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?

    static var enabled: Bool { UserDefaults.standard.object(forKey: "floatingCircle") as? Bool ?? true }

    /// Small, medium, large and extra large.
    static let sizes: [CGFloat] = [100, 132, 168, 212]
    static let sizeNames = ["Small", "Medium", "Large", "Extra large"]
    static func diameter(forSize size: Int) -> CGFloat { sizes[max(0, min(sizes.count - 1, size))] }
    /// Room around the circle so its soft shadow is not clipped by the window.
    static let margin: CGFloat = 18

    private var diameter: CGFloat {
        Self.diameter(forSize: UserDefaults.standard.object(forKey: "floatingSize") as? Int ?? 0)
    }

    /// Shows, hides or resizes the circle to match the settings. Safe to call at any time.
    func refresh() {
        let d = UserDefaults.standard
        // It steps aside whenever full screen breathing is on, so the two never compete.
        guard Self.enabled, !BreatheOverlay.shared.isShowing else { hide(); return }
        let side = diameter + Self.margin * 2
        let first = panel == nil
        if first { build(side: side) }
        guard let panel else { return }
        if abs(panel.frame.width - side) > 0.5 {
            // Keep the circle's top left corner where it is when the size changes.
            let top = panel.frame.maxY, left = panel.frame.minX
            panel.setFrame(NSRect(x: left, y: top - side, width: side, height: side), display: true)
        }
        panel.ignoresMouseEvents = d.bool(forKey: "floatingClickThrough")
        let target = CGFloat(d.object(forKey: "floatingOpacity") as? Double ?? 0.9)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = target }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in
            // Only close it if nothing asked for it again in the meantime.
            Task { @MainActor in
                if let self, !Self.enabled || BreatheOverlay.shared.isShowing { self.panel?.orderOut(nil) }
            }
        })
    }

    private func build(side: CGFloat) {
        let p = NSPanel(contentRect: NSRect(origin: startOrigin(side: side), size: NSSize(width: side, height: side)),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = FirstMouseHostingView(rootView: FloatingCircleView(timer: AppModel.shared.timer))
        host.sizingOptions = []
        p.contentView = host
        panel = p
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak p] _ in
            guard let p else { return }
            UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "floatingOrigin")
        }
    }

    /// Where you left it, or the top right of the main screen the first time.
    private func startOrigin(side: CGFloat) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: "floatingOrigin") {
            let p = NSPointFromString(s)
            let r = NSRect(origin: p, size: NSSize(width: side, height: side))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) { return p }
        }
        let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: f.maxX - side - 8, y: f.maxY - side - 8)
    }
}

/// The picture inside the floating circle: frosted glass, a fine edge light, and a soft shadow.
struct FloatingCircleView: View {
    @ObservedObject var timer: PomodoroTimer
    @AppStorage("floatingSize") private var sizeChoice = 0
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.bloom.rawValue
    @AppStorage("breathPattern") private var patternID = "settle"
    @State private var start = Date()
    @State private var hovering = ProcessInfo.processInfo.environment["TARN_PREVIEW_HOVER"] == "1"   // only for taking preview pictures
    @ObservedObject private var sound = AppModel.shared.sound

    private var d: CGFloat { FloatingCircle.diameter(forSize: sizeChoice) }
    private var pattern: BreathPattern { BreathPattern.all.first { $0.id == patternID } ?? .settle }
    private var isBreathe: Bool { timer.mode == .breathe }

    var body: some View {
        ZStack {
            disc
            Group {
                if isBreathe { breathe.transition(.opacity) } else { focus.transition(.opacity) }
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
        }
        .frame(width: d, height: d)
        .overlay(alignment: .topTrailing) { closeButton }
        .scaleEffect(hovering && !isBreathe ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .animation(.easeInOut(duration: 0.5), value: isBreathe)
        .padding(FloatingCircle.margin)
        .contentShape(Circle().inset(by: FloatingCircle.margin))
        .onHover { hovering = $0 }
        .onTapGesture { if !isBreathe { timer.toggle() } }
        .help(isBreathe ? "Drag to move" : "Click to start or pause. Drag to move.")
        .contextMenu {
            Button("Hide floating circle") { Self.hide() }
            Menu("Size") {
                ForEach(0..<FloatingCircle.sizeNames.count, id: \.self) { i in
                    Button(FloatingCircle.sizeNames[i]) { sizeChoice = i; FloatingCircle.shared.refresh() }
                }
            }
        }
    }

    static func hide() {
        UserDefaults.standard.set(false, forKey: "floatingCircle")
        FloatingCircle.shared.refresh()
    }

    /// A small close button that appears on hover. Hiding the circle is always one click away.
    private var closeButton: some View {
        Button { Self.hide() } label: {
            Image(systemName: "xmark")
                .font(.system(size: max(8, d * 0.075), weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: max(18, d * 0.17), height: max(18, d * 0.17))
                .background(Circle().fill(Color.black.opacity(0.55)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(d * 0.04)
        .opacity(hovering ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: hovering)
        .help("Hide the floating circle. Turn it back on in Settings, Focus.")
        .accessibilityLabel("Hide floating circle")
    }

    /// Frosted glass over whatever is behind it, tinted dark enough to keep the numbers easy to read.
    private var disc: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color(red: 0.05, green: 0.07, blue: 0.13).opacity(0.62))
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.04), .white.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 10, y: 4)
    }

    private var focus: some View {
        ZStack {
            LensView(progress: timer.progress, running: timer.isRunning).padding(d * 0.006)
            VStack(spacing: d * 0.015) {
                Text(timer.phase.isBreak ? timer.phase.rawValue.uppercased() : "FOCUS")
                    .font(.system(size: max(8, d * 0.062), weight: .semibold)).tracking(1.3)
                    .foregroundStyle(timer.phase.isBreak ? Color.purple : Color.focusTint)
                Text(timer.clockText)
                    .font(.system(size: d * 0.205, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(.white.opacity(0.96))
                HStack(spacing: d * 0.07) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .opacity(hovering || !timer.isRunning ? 0.75 : 0)
                    soundButton.opacity(hovering ? 1 : 0)
                }
                .font(.system(size: max(8, d * 0.075)))
                .foregroundStyle(.white)
                .animation(.easeOut(duration: 0.2), value: hovering)
            }
        }
    }

    /// A small speaker that appears on hover. It turns the sound on or off without opening Tarn.
    private var soundButton: some View {
        Button { sound.toggle() } label: {
            Image(systemName: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(sound.isPlaying ? 0.9 : 0.6))
        .help(sound.isPlaying ? "Sound on. Click to turn it off." : "Sound off. Click to turn it on.")
        .accessibilityLabel(sound.isPlaying ? "Turn sound off" : "Turn sound on")
    }

    private var breathe: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let s = pattern.state(at: t)
            ZStack {
                switch BreathStyle(rawValue: styleRaw) ?? .bloom {
                case .fill: FillCanvas(scale: s.scale, time: t).padding(d * 0.04)
                case .bloom: BloomCanvas(scale: s.scale, time: t).padding(-d * 0.04)
                }
                Text(s.label.lowercased())
                    .font(.system(size: max(9, d * 0.075), weight: .light, design: .serif)).tracking(1)
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: d * 0.35)
                soundButton
                    .font(.system(size: max(9, d * 0.085)))
                    .opacity(hovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: hovering)
                    .offset(y: -d * 0.41)
            }
        }
    }
}
