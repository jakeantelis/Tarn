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
        let p = FloatingPanel(contentRect: NSRect(origin: startOrigin(side: side), size: NSSize(width: side, height: side)),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hover = FloatingHover()
        let host = FloatingHostingView(rootView: FloatingCircleView(timer: AppModel.shared.timer, hover: hover))
        host.onHover = { [weak hover] inside in hover?.inside = inside }
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

/// Whether the pointer is over the circle. Fed by a tracking area that works even when Tarn is not the front app.
@MainActor
final class FloatingHover: ObservableObject {
    @Published var inside = false
}

/// Hosts the circle and reports the pointer entering and leaving, even while another app is in front.
final class FloatingHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The picture inside the floating circle: frosted glass, a fine edge light, and a soft shadow.
struct FloatingCircleView: View {
    @ObservedObject var timer: PomodoroTimer
    @AppStorage("floatingSize") private var sizeChoice = 0
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.bloom.rawValue
    @AppStorage("breathPattern") private var patternID = "settle"
    @State private var start = Date()
    @ObservedObject var hover: FloatingHover
    @ObservedObject private var sound = AppModel.shared.sound

    private var d: CGFloat { FloatingCircle.diameter(forSize: sizeChoice) }
    private var pattern: BreathPattern { BreathPattern.all.first { $0.id == patternID } ?? .settle }
    private var isBreathe: Bool { timer.mode == .breathe }
    private var hovering: Bool { hover.inside }

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
        .overlay { closeButton.offset(x: d * 0.238, y: -d * 0.283) }   // inside the round edge, so every part of it can be clicked
        .scaleEffect(hovering && !isBreathe ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .animation(.easeInOut(duration: 0.5), value: isBreathe)
        .padding(FloatingCircle.margin)
        .contentShape(Circle().inset(by: FloatingCircle.margin))
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
                .frame(width: max(22, d * 0.19), height: max(22, d * 0.19))
                .background(Circle().fill(Color.black.opacity(0.55)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .opacity(hovering ? 1 : 0.55)
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

/// The floating window. SwiftUI swallows mouse presses, so the window cannot rely on "drag by background".
/// This panel does its own dragging: a press that moves more than a few points drags the circle, and a press
/// that does not move is a normal click, passed on to the circle or its buttons.
final class FloatingPanel: NSPanel {
    /// Where the pointer is, in screen points. Replaced in tests.
    var pointer: () -> NSPoint = { NSEvent.mouseLocation }
    private var pressEvent: NSEvent?
    private var pressPointer = NSPoint.zero
    private var pressOrigin = NSPoint.zero
    private(set) var isDragging = false
    static let dragThreshold: CGFloat = 3

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pressEvent = event
            pressPointer = pointer()
            pressOrigin = frame.origin
            isDragging = false
        case .leftMouseDragged:
            guard pressEvent != nil else { super.sendEvent(event); return }
            let m = pointer()
            let dx = m.x - pressPointer.x, dy = m.y - pressPointer.y
            if !isDragging, hypot(dx, dy) > Self.dragThreshold { isDragging = true }
            if isDragging { setFrameOrigin(NSPoint(x: pressOrigin.x + dx, y: pressOrigin.y + dy)) }
        case .leftMouseUp:
            guard let down = pressEvent else { super.sendEvent(event); return }
            pressEvent = nil
            if isDragging {
                isDragging = false
                keepOnScreen()
            } else {
                super.sendEvent(down)      // a plain click: deliver the press and the release together
                super.sendEvent(event)
            }
        default:
            super.sendEvent(event)
        }
    }

    /// If the circle was dropped mostly off every screen, bring it back to the nearest edge.
    private func keepOnScreen() {
        let screens = NSScreen.screens.map { $0.visibleFrame }
        guard !screens.isEmpty else { return }
        let visible = screens.map { frame.intersection($0) }.map { $0.isNull ? 0 : $0.width * $0.height }.max() ?? 0
        guard visible < frame.width * frame.height * 0.35 else { return }
        let target = screens.min { distance(from: frame.origin, to: $0) < distance(from: frame.origin, to: $1) }!
        let x = min(max(frame.origin.x, target.minX), target.maxX - frame.width)
        let y = min(max(frame.origin.y, target.minY), target.maxY - frame.height)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func distance(from p: NSPoint, to r: NSRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}
