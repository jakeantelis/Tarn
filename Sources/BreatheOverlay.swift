import SwiftUI
import AppKit
import os

/// Full screen, distraction free breathing. Optionally hides other apps and restores them on exit.
@MainActor
final class BreatheOverlay: ObservableObject {
    static let shared = BreatheOverlay()
    private static let log = Logger(subsystem: "com.antelislabs.tarn", category: "overlay")
    private var windows: [NSWindow] = []
    private var hidden: [NSRunningApplication] = []
    private var monitor: Any?
    private var cueTimer: Timer?
    /// One shared clock, so every screen shows the same breath.
    private(set) var startDate = Date()
    /// Set while guided breathing is paused in full screen; the breath, the voice and the sounds hold.
    @Published private(set) var pausedFrom: Date?
    private var soundWasOn = false
    /// Set by Calm mode so the "calm ends" Shortcut runs when the overlay closes.
    var calmActive = false

    var isShowing: Bool { !windows.isEmpty }

    /// The master switch in Settings. When it is off, Tarn never covers the screen or hides other apps.
    static var allowed: Bool { UserDefaults.standard.object(forKey: "allowScreenTakeover") as? Bool ?? true }

    func show() {
        guard Self.allowed else { Self.log.notice("full screen refused: switched off in Settings"); return }
        guard !isShowing else { Self.log.notice("full screen ignored: already showing"); return }
        // With the spoken cue, the first breath waits while the voice names the exercise.
        let id = UserDefaults.standard.string(forKey: "breathPattern") ?? "settle"
        let lead = Self.guidedMode ? 0 : BreathVoice.leadIn(BreathPattern.all.first { $0.id == id } ?? .settle)
        startDate = Date().addingTimeInterval(lead)
        pausedFrom = nil
        soundWasOn = false
        if UserDefaults.standard.object(forKey: "hideOthersWhenBreathing") as? Bool ?? true {
            hidden = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && !$0.isHidden && $0 != NSRunningApplication.current
            }
            hidden.forEach { $0.hide() }
        }
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.onEscape = { [weak self] in self?.close("escape or click") }
            w.level = .screenSaver
            w.backgroundColor = .clear
            w.isOpaque = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = FirstMouseHostingView(rootView: OverlayView(onClose: { [weak self] in self?.close("close button") }))
            host.sizingOptions = []          // the window decides the size, never the content
            w.contentView = host
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        Self.log.notice("full screen shown on \(NSScreen.screens.count) screen(s)")
        FloatingCircle.shared.refresh()
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
            if e.keyCode == 53 { self?.close("escape key"); return nil }   // Esc
            if e.keyCode == 49 { self?.spaceKey(); return nil }                // Space skips the intro, or pauses
            return e
        }
        // One clock for the breath cues, however many screens are covered.
        cueTimer?.invalidate()
        cueTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.cueTick() }
        }
    }

    /// In Guided (the switch on the Breathe screen) or during a meditation, the guided cue plays and there is no spoken intro.
    static var guidedMode: Bool {
        Meditation.shared.isActive
            || (UserDefaults.standard.string(forKey: BreatheSettings.mode) == BreatheMode.guided.rawValue && Meditation.isAvailable)
    }

    private func cueTick() {
        let meditation = Meditation.shared
        let guided = meditation.isActive
        let id = UserDefaults.standard.string(forKey: "breathPattern") ?? "settle"
        let pattern = guided ? BreathPattern.settle : (BreathPattern.all.first { $0.id == id } ?? .settle)
        let t = guided ? meditation.elapsed() : elapsed()
        AppModel.shared.cueTick(.fullScreen, t: t, pattern: pattern, guided: Self.guidedMode, running: isShowing && !isPaused)
    }

    /// Seconds since the first breath of guided breathing. Negative during the intro. Holds still while paused.
    func elapsed(at date: Date = Date()) -> Double { (pausedFrom ?? date).timeIntervalSince(startDate) }

    var isPaused: Bool { Meditation.shared.isActive ? Meditation.shared.isPaused : pausedFrom != nil }

    /// True while the voice names the exercise before the first breath.
    func introPlaying(at date: Date = Date()) -> Bool {
        isShowing && !Self.guidedMode && BreatheSettings.spokenOn && pausedFrom == nil && elapsed(at: date) < -0.7
    }

    /// Cuts the spoken intro short; the first breath starts a moment later. False when no intro is playing.
    @discardableResult func skipIntro() -> Bool {
        guard introPlaying() else { return false }
        AppModel.shared.cues.stopVoice()
        startDate = Date().addingTimeInterval(0.6)
        return true
    }

    /// Pauses or resumes: the breath and its sounds, or the meditation's voice and breath together.
    func togglePause() {
        let meditation = Meditation.shared
        let sound = AppModel.shared.sound
        // A paused session is really quiet: the sound holds too, and comes back on resume.
        if isPaused {
            if meditation.isActive { meditation.togglePause() } else if let at = pausedFrom {
                startDate = startDate.addingTimeInterval(Date().timeIntervalSince(at))
                pausedFrom = nil
            }
            if soundWasOn { soundWasOn = false; sound.play() }
        } else {
            if meditation.isActive { meditation.togglePause() } else {
                AppModel.shared.cues.stopVoice()
                pausedFrom = Date()
            }
            soundWasOn = sound.isPlaying
            if soundWasOn { sound.pause() }
        }
        objectWillChange.send()
    }

    private func spaceKey() { if !skipIntro() { togglePause() } }

    func close(_ reason: String = "api") {
        Self.log.notice("full screen closed: \(reason, privacy: .public)")
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cueTimer?.invalidate()
        cueTimer = nil
        AppModel.shared.cueStop(.fullScreen)
        // Leaving while paused brings back the sound the pause held (a meditation stays paused on the Breathe screen).
        if pausedFrom != nil, soundWasOn, !Meditation.shared.isActive { AppModel.shared.sound.play() }
        pausedFrom = nil; soundWasOn = false
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; ws.forEach { $0.animator().alphaValue = 0 } },
                                             completionHandler: { ws.forEach { $0.orderOut(nil) } })
        hidden.forEach { $0.unhide() }
        hidden = []
        FloatingCircle.shared.refresh()
        if calmActive {
            calmActive = false
            runShortcutNamed(UserDefaults.standard.string(forKey: "calmEndShortcut") ?? "")
            // The sound fading out is the quiet signal that Calm is over and it is time to get back,
            // unless the user chose to keep it playing.
            if !UserDefaults.standard.bool(forKey: "keepSoundAfterSession") { AppModel.shared.sound.stop() }
        }
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
    @ObservedObject private var meditation = Meditation.shared
    let onClose: () -> Void
    @AppStorage("breathPattern") private var patternID = "settle"
    @AppStorage("guideMe") private var guideMe = false
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.bloom.rawValue
    @ObservedObject private var overlay = BreatheOverlay.shared
    private var pattern: BreathPattern { meditation.isActive ? .settle : (BreathPattern.all.first { $0.id == patternID } ?? .settle) }

    var body: some View {
        ZStack {
            // Fully covers the desktop (icons, windows and wallpaper) with a calm dusk gradient.
            LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24), Color(red: 0.04, green: 0.06, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()   // fully opaque, so nothing from the desktop shows through
            GeometryReader { geo in
            // The picture scales with the screen, so it is generous on a big display and still fits a small one.
            let side = max(320, min(geo.size.height * 0.56, geo.size.width * 0.6, 760))
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                // In a guided session the picture follows the voice, holding still through the lead-in.
                let guided = meditation.isActive
                let t = guided ? meditation.elapsed(at: ctx.date) : overlay.elapsed(at: ctx.date)
                let s = t < 0 ? (label: "Get comfortable", scale: 0.0) : pattern.state(at: max(0, t))
                VStack(spacing: 6) {
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
                            .frame(width: side * 1.65, height: side * 1.65)
                            .allowsHitTesting(false)
                        }
                        switch BreathStyle(rawValue: styleRaw) ?? .bloom {
                        case .fill: FillCanvas(scale: s.scale, time: t)
                        case .bloom: BloomCanvas(scale: s.scale, time: t)
                        }
                    }
                    .frame(width: side, height: side)
                    Text(s.label.lowercased())
                        .font(.system(size: max(38, side * 0.075), weight: .light, design: .serif))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.35), radius: 8)
                        .frame(height: max(48, side * 0.1))
                        .id(s.label)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.9), value: s.label)
                    if overlay.introPlaying(at: ctx.date) {
                        Text("Intro")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(minHeight: 48)
                    } else if guided {
                        Text(meditation.caption)
                            .font(.system(size: 17, weight: .light, design: .serif).italic())
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 560, minHeight: 48)
                            .id(meditation.caption)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 1.2), value: meditation.caption)
                    } else if guideMe {
                        Text(Guidance.line(at: t))
                            .font(.system(size: 17, weight: .light, design: .serif).italic())
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(height: 24)
                            .id(Guidance.index(at: t))
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 1.2), value: Guidance.index(at: t))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            }
            VStack {
                Spacer()
                Text(overlay.introPlaying() ? "Space skips the intro. Esc or a click leaves."
                     : "Space pauses. Esc or a click anywhere leaves.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.55)).padding(.bottom, 28)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Sound controls and a way out, always in the same corner.
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    if overlay.introPlaying(at: ctx.date) {
                        Button("Skip intro") { overlay.skipIntro() }
                            .buttonStyle(CapsuleButtonStyle(small: true))
                    } else {
                        Button { overlay.togglePause() } label: {
                            Label(overlay.isPaused ? "Resume" : "Pause", systemImage: overlay.isPaused ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(CapsuleButtonStyle(small: true))
                    }
                }
                Menu {
                    ForEach(SoundPreset.all) { p in
                        Button(p.name) { sound.applyPreset(p) }
                    }
                    Divider()
                    Button("Sound off") { sound.pause() }
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
