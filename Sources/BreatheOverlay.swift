import SwiftUI
import AppKit

/// Full screen, distraction free breathing. Optionally hides other apps and restores them on exit.
@MainActor
final class BreatheOverlay {
    static let shared = BreatheOverlay()
    private var windows: [NSWindow] = []
    private var hidden: [NSRunningApplication] = []
    private var monitor: Any?
    /// One shared clock, so every screen shows the same breath.
    private(set) var startDate = Date()
    /// Set by Calm mode so the "calm ends" Shortcut runs when the overlay closes.
    var calmActive = false

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        guard !isShowing else { return }
        startDate = Date()
        if UserDefaults.standard.object(forKey: "hideOthersWhenBreathing") as? Bool ?? true {
            hidden = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && !$0.isHidden && $0 != NSRunningApplication.current
            }
            hidden.forEach { $0.hide() }
        }
        for (index, screen) in NSScreen.screens.enumerated() {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.onEscape = { [weak self] in self?.close() }
            w.level = .screenSaver
            w.backgroundColor = .clear
            w.isOpaque = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = FirstMouseHostingView(rootView: OverlayView(speaks: index == 0, onClose: { [weak self] in self?.close() }))
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Hiding other apps can hand focus to Finder. Take it back so Esc reaches this window.
        for delay in [0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isShowing else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.close(); return nil }   // Esc
            return e
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; ws.forEach { $0.animator().alphaValue = 0 } },
                                             completionHandler: { ws.forEach { $0.orderOut(nil) } })
        hidden.forEach { $0.unhide() }
        hidden = []
        VoiceGuide.shared.reset()
        if calmActive { calmActive = false; runShortcutNamed(UserDefaults.standard.string(forKey: "calmEndShortcut") ?? "") }
    }
}

/// Accepts the very first click even when Tarn is not the active app, so a click always reaches the overlay.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class OverlayWindow: NSWindow {
    var onEscape: (() -> Void)?
    /// Clicks anywhere close the overlay except in this top right strip, where the sound controls live.
    static let controlsSize = NSSize(width: 420, height: 110)
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let p = event.locationInWindow
            let inControls = p.x > frame.width - Self.controlsSize.width && p.y > frame.height - Self.controlsSize.height
            if !inControls { onEscape?(); return }
        }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

struct OverlayView: View {
    @ObservedObject private var sound = AppModel.shared.sound
    let speaks: Bool
    let onClose: () -> Void
    @AppStorage("breathPattern") private var patternID = "settle"
    @AppStorage("guideMe") private var guideMe = false
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.bloom.rawValue
    @MainActor private var start: Date { BreatheOverlay.shared.startDate }
    private var pattern: BreathPattern { BreathPattern.all.first { $0.id == patternID } ?? .settle }

    var body: some View {
        ZStack {
            // Fully covers the desktop (icons, windows and wallpaper) with a calm dusk gradient.
            LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24), Color(red: 0.04, green: 0.06, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(0.97)
                .ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                let s = pattern.state(at: t)
                VStack(spacing: 28) {
                    ZStack {
                        // Soft ripples drift outward from the picture, timed to the breath.
                        if !reduceMotion {
                            Canvas { g, size in
                                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                                for k in 0..<3 {
                                    let ph = ((t / 7) + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                                    let r = size.width * (0.27 + 0.09 * s.scale + 0.12 * ph)
                                    var ring = Path(); ring.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                                    g.stroke(ring, with: .color(Color(red: 0.72, green: 0.80, blue: 1.0).opacity(0.18 * (1 - ph))), lineWidth: 1.4)
                                }
                            }
                            .frame(width: 900, height: 900)
                            .allowsHitTesting(false)
                        }
                        switch BreathStyle(rawValue: styleRaw) ?? .bloom {
                        case .fill: FillCanvas(scale: s.scale, time: t)
                        case .bloom: BloomCanvas(scale: s.scale, time: t)
                        }
                    }
                    .frame(width: 540, height: 540)
                    Text(s.label.lowercased())
                        .font(.system(size: 34, weight: .ultraLight, design: .serif))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.75))
                        .id(s.label)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.9), value: s.label)
                    if guideMe {
                        Text(Guidance.line(at: t))
                            .font(.system(size: 17, weight: .light, design: .serif).italic())
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(height: 24)
                            .id(Guidance.index(at: t))
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 1.2), value: Guidance.index(at: t))
                    }
                }
                .onChange(of: s.label) { _, new in if speaks { VoiceGuide.shared.cue(new) } }
                .onChange(of: Guidance.index(at: t)) { _, _ in if guideMe && speaks { VoiceGuide.shared.say(Guidance.line(at: t)) } }
            }
            VStack {
                Spacer()
                Text("Press Esc or click anywhere to leave")
                    .font(.footnote).foregroundStyle(.white.opacity(0.55)).padding(.bottom, 28)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Sound controls and a way out, always in the same corner.
            HStack(spacing: 8) {
                Menu {
                    ForEach(SoundPreset.all) { p in
                        Button(p.name) { sound.applyPreset(p) }
                    }
                    Divider()
                    Button("Sound off") { sound.stop() }
                } label: {
                    Label("Sounds", systemImage: "music.note")
                }
                .menuStyle(.button).buttonStyle(CapsuleButtonStyle(small: true)).menuIndicator(.hidden).fixedSize()
                Button { sound.toggle() } label: {
                    Image(systemName: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .buttonStyle(CircleButtonStyle(on: sound.isPlaying))
                .help(sound.isPlaying ? "Turn sound off" : "Turn sound on")
                Button("Close", action: onClose)
                    .buttonStyle(CapsuleButtonStyle(prominent: true, small: true))
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .tint(Color.breatheTint)
    }
}
