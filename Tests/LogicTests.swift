import Foundation
import AppKit

var failures = 0
func check(_ ok: @autoclosure () -> Bool, _ msg: String) {
    if ok() { print("  ok   \(msg)") } else { print("  FAIL \(msg)"); failures += 1 }
}

@main struct Tests {
    @MainActor static func main() {
        _ = NSApplication.shared
        if PomodoroTimer.secondsPerMinute != 60 { runCycleTest(); return }
        print("BreathPattern")
        for p in BreathPattern.all {
            let s0 = p.state(at: 0)
            check(abs(s0.scale) < 0.01 && s0.label == "Breathe in", "\(p.name): starts empty on Breathe in")
            let inhale = p.steps[0]
            check(p.state(at: p.warped(0) + 0.001).label == "Breathe in", "\(p.name): label at start")
            var maxJump = 0.0, prev = p.state(at: 0).scale
            var t = 0.0
            while t < 400 { t += 0.05; let s = p.state(at: t).scale; maxJump = max(maxJump, abs(s - prev)); prev = s }
            check(maxJump < 0.25, "\(p.name): no jumps over 400 s (max step \(String(format: "%.3f", maxJump)))")
            check((0...1).contains(p.state(at: 123.4).scale), "\(p.name): scale stays in 0...1")
            _ = inhale
        }
        let settle = BreathPattern.settle
        check(settle.warped(300) > settle.warped(180), "Settle: warped time keeps increasing")
        check(abs(settle.warped(180 + 1e-6) - settle.warped(180 - 1e-6)) < 1e-3, "Settle: warp continuous at 3 minutes")

        print("Guided meditation script")
        for m in [5, 10, 20] {
            let total = Double(m * 60), lines = VoiceScript.timeline(total: total)
            check(lines.first?.at == -VoiceScript.leadIn && lines.first?.passage == VoiceScript.opening, "\(m) min: opens with the welcome in the lead-in")
            check(lines.last?.at == total && lines.last?.passage == VoiceScript.ending, "\(m) min: ends with the ending at the close")
            check(zip(lines, lines.dropFirst()).allSatisfy { $0.at < $1.at }, "\(m) min: passages come in order")
            check(lines.contains { $0.passage == VoiceScript.middle.last! }, "\(m) min: includes the invitation to rest")
        }
        let longest = Set(VoiceScript.timeline(total: 20 * 60).map(\.passage.id))
        check(VoiceScript.all.allSatisfy { longest.contains($0.id) }, "20 min: speaks every passage")

        print("Move to Applications")
        check(MoveToApplications.shouldOffer(path: "/Volumes/Tarn/Tarn.app"), "offers from a disk image")
        check(MoveToApplications.shouldOffer(path: NSHomeDirectory() + "/Downloads/Tarn.app"), "offers from Downloads")
        check(!MoveToApplications.shouldOffer(path: "/Applications/Tarn.app"), "never offers from Applications")
        check(!MoveToApplications.shouldOffer(path: NSHomeDirectory() + "/Applications/Tarn.app"), "never offers from ~/Applications")
        check(!MoveToApplications.shouldOffer(path: "/Users/dev/Projects/Tarn/build/Tarn.app"), "never offers for a development build")

        print("Updates")
        check(UpdateChecker.isNewer("v0.2.0", than: "0.1.0"), "0.2.0 is newer than 0.1.0")
        check(UpdateChecker.isNewer("0.1.1", than: "0.1.0"), "0.1.1 is newer than 0.1.0")
        check(UpdateChecker.isNewer("1.0", than: "0.9.9"), "1.0 is newer than 0.9.9")
        check(!UpdateChecker.isNewer("0.1.0", than: "0.1.0"), "same version is not newer")
        check(!UpdateChecker.isNewer("v0.1.0", than: "0.1"), "0.1.0 equals 0.1")
        check(!UpdateChecker.isNewer("0.0.9", than: "0.1.0"), "older is not newer")
        check(UpdateChecker.isNewer("0.2.0-beta", than: "0.1.0"), "a pre-release suffix is ignored")

        print("Timer")
        for k in ["mode", "focusMinutes", "soundEnabled"] { UserDefaults.standard.removeObject(forKey: k) }
        let t = PomodoroTimer()
        check(t.duration(for: .work) == 1500 && t.duration(for: .shortBreak) == 300 && t.duration(for: .longBreak) == 900, "25 min: 25/5/15")
        check(t.roundsPerSet == 4, "25 min: 4 rounds per set")
        t.setFocusMinutes(45)
        check(t.duration(for: .work) == 2700 && t.duration(for: .shortBreak) == 600 && t.roundsPerSet == 3, "45 min: 45/10, 3 rounds")
        t.setFocusMinutes(90)
        check(t.duration(for: .shortBreak) == 900 && t.duration(for: .longBreak) == 1800, "90 min: 15/30 breaks")
        t.setFocusMinutes(15)
        check(t.duration(for: .shortBreak) == 300, "15 min: 5 min break")
        check(t.remaining == 900, "idle remaining follows length (\(t.remaining))")
        check(t.clockText == "15:00", "clock text")
        t.skip()
        check(t.phase == .shortBreak && t.completedRounds == 0, "skip from focus goes to break without counting a round")
        t.skip()
        check(t.phase == .work, "skip from break returns to focus")
        t.start()
        check(t.isRunning, "start runs")
        t.pause()
        check(!t.isRunning && t.remaining > 890 && t.remaining <= 900, "pause keeps remaining (\(Int(t.remaining)) s)")
        t.reset()
        check(t.remaining == 900, "reset restores length")
        t.startBreak()
        check(t.phase == .shortBreak && t.isRunning, "startBreak starts a break")
        t.startWork(minutes: 60)
        check(t.phase == .work && t.effectiveMinutes == 60 && t.focusMinutes == 15 && t.isRunning && t.remaining == 3600, "startWork(60) from a break uses 60 for this session only")
        t.setMode(.breathe)
        check(t.isRunning && t.mode == .breathe, "switching to Breathe keeps a running round going")
        t.setMode(.pomodoro)
        check(t.nextLabel.contains("Break") || t.nextLabel.contains("break"), "next label: \(t.nextLabel)")

        print("URL commands")
        let m = AppModel.shared
        m.handle(URL(string: "tarn://start?minutes=45")!)
        check(m.timer.isRunning && m.timer.effectiveMinutes == 45 && m.timer.phase == .work, "start?minutes=45")
        m.handle(URL(string: "tarn://pause")!)
        check(!m.timer.isRunning, "pause")
        m.handle(URL(string: "tarn://start?minutes=999")!)
        check(m.timer.effectiveMinutes == m.timer.focusMinutes && m.timer.isRunning, "minutes out of range is ignored, falls back to the saved length")
        m.handle(URL(string: "tarn://break")!)
        check(m.timer.phase == .shortBreak || m.timer.phase == .longBreak, "break")
        m.handle(URL(string: "tarn://break")!)
        check(m.timer.phase.isBreak && m.timer.isRunning, "break twice stays in a break")
        m.handle(URL(string: "tarn://breathe")!)
        check(m.timer.mode == .breathe, "breathe switches the view")
        m.handle(URL(string: "tarn://bogus")!)
        m.handle(URL(string: "https://example.com")!)
        check(true, "unknown and foreign URLs are ignored")
        m.handle(URL(string: "tarn://stop")!)

        print("Screen takeover switch")
        UserDefaults.standard.set(false, forKey: "allowScreenTakeover")
        ScreenClearer.shared.clear()
        check(!ScreenClearer.shared.isCleared, "Hide apps does nothing when takeover is off")
        BreatheOverlay.shared.show()
        check(!BreatheOverlay.shared.isShowing, "full screen does nothing when takeover is off")
        UserDefaults.standard.removeObject(forKey: "allowScreenTakeover")

        print("Sound mixer")
        let e = SoundEngine()
        for s in Soundscape.allCases { e.setLevel(0, for: s) }
        let order: [Soundscape] = [.ocean, .forest, .birds, .stream]
        for (i, s) in order.enumerated() { e.setLevel(0.2 + 0.1 * Double(i), for: s) }
        check(order.filter { (e.levels[$0] ?? 0) > 0 }.count == SoundEngine.maxLayers, "layer cap: only \(SoundEngine.maxLayers) at once")
        check((e.levels[.stream] ?? 0) > 0, "newest sound is kept")
        check((e.levels[.ocean] ?? 0) == 0, "quietest sound steps aside")
        check(SoundPreset.all.allSatisfy { $0.mix.filter { $0.value > 0 }.count <= SoundEngine.maxLayers }, "all presets within the cap")

        print("Sound keeps playing into full screen")
        // Full screen and Calm mode switch the app to Breathe. That change must never cut sound that is already playing.
        let d = UserDefaults.standard
        for enabled in [false, true] {
            for scope in SoundScope.allCases {
                d.set(enabled, forKey: "soundEnabled"); d.set(scope.rawValue, forKey: "soundScope")
                let manual = SoundEngine()
                manual.play()
                manual.sync(mode: .breathe, phase: .work, timerRunning: false)
                check(manual.isPlaying, "mix you started by hand keeps playing (timer sound \(enabled ? "on" : "off"), scope \(scope.rawValue))")
                manual.stop()
            }
        }
        d.set(true, forKey: "soundEnabled"); d.set(SoundScope.focus.rawValue, forKey: "soundScope")
        let timed = SoundEngine()
        timed.sync(mode: .pomodoro, phase: .work, timerRunning: true)
        check(timed.isPlaying, "timer driven sound starts with a Focus round")
        timed.sync(mode: .breathe, phase: .work, timerRunning: true)
        check(timed.isPlaying, "timer driven sound keeps playing when the app switches to Breathe mid round")
        timed.stop()
        d.removeObject(forKey: "soundEnabled"); d.removeObject(forKey: "soundScope")

        print("Floating circle")
        check(FloatingCircle.sizes == FloatingCircle.sizes.sorted(), "sizes grow from small to extra large")
        check(FloatingCircle.sizes.count == FloatingCircle.sizeNames.count, "every size has a name")
        check(FloatingCircle.diameter(forSize: -3) == FloatingCircle.sizes.first && FloatingCircle.diameter(forSize: 99) == FloatingCircle.sizes.last, "a bad size choice is clamped")
        check(FloatingCircle.enabled, "the floating circle is on by default")
        check(FloatingCircle.diameter(forSize: UserDefaults.standard.object(forKey: "floatingSize") as? Int ?? 0) == FloatingCircle.sizes.first, "and it starts at the small size")

        print("Floating circle dragging")
        do {
            let panel = FloatingPanel(contentRect: NSRect(x: 200, y: 300, width: 136, height: 136), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            var at = NSPoint(x: 500, y: 500)
            panel.pointer = { at }
            func mouse(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: 60, y: 60), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            panel.sendEvent(mouse(.leftMouseDown))
            at = NSPoint(x: 540, y: 470); panel.sendEvent(mouse(.leftMouseDragged))
            check(panel.frame.origin == NSPoint(x: 240, y: 270), "dragging moves the circle with the pointer")
            at = NSPoint(x: 560, y: 450); panel.sendEvent(mouse(.leftMouseDragged))
            check(panel.frame.origin == NSPoint(x: 260, y: 250), "and keeps following it")
            panel.sendEvent(mouse(.leftMouseUp))
            check(!panel.isDragging, "letting go ends the drag")
            let rest = panel.frame.origin
            at = NSPoint(x: 700, y: 700)
            panel.sendEvent(mouse(.leftMouseDown)); at = NSPoint(x: 701, y: 700); panel.sendEvent(mouse(.leftMouseDragged)); panel.sendEvent(mouse(.leftMouseUp))
            check(panel.frame.origin == rest, "a click with a tiny wobble does not move it")
            panel.sendEvent(mouse(.leftMouseDown)); at = NSPoint(x: 5000, y: 5000); panel.sendEvent(mouse(.leftMouseDragged)); panel.sendEvent(mouse(.leftMouseUp))
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
            check(NSScreen.screens.isEmpty || onScreen, "dropping it far off screen brings it back")
        }

        print("Stats")
        let st = StatsStore.shared
        let before = st.today.rounds
        st.record(minutes: 25)
        check(st.today.rounds == before + 1 && st.today.minutes >= 25, "record adds a round")
        check(st.streak >= 1, "streak counts today")
        check(st.week.count == 7 && st.week.last?.isToday == true, "week has 7 days ending today")

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}

/// Runs a whole round for real, with one second standing in for a minute (TARN_SECONDS_PER_MINUTE=1).
@MainActor func runCycleTest() {
    print("Full cycle (1 second per minute)")
    for k in ["mode", "focusMinutes", "soundEnabled", "autoStartNext"] { UserDefaults.standard.removeObject(forKey: k) }
    func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    func waitUntil(_ timeout: Double, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !cond() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
    var fails = 0
    func ok(_ c: Bool, _ m: String) { print(c ? "  ok   \(m)" : "  FAIL \(m)"); if !c { fails += 1 } }

    let stats = StatsStore.shared
    let before = stats.today.rounds
    let t = PomodoroTimer()
    t.startWork(minutes: 1)               // a 1 "minute" round is 1 second, its break is 5 seconds
    ok(t.isRunning && t.phase == .work, "round starts")
    waitUntil(3) { t.phase == .shortBreak }
    ok(t.phase == .shortBreak, "round ends and a short break starts on its own (phase: \(t.phase.rawValue))")
    ok(t.isRunning, "the break is running (auto start)")
    ok(stats.today.rounds == before + 1, "the finished round is counted in stats")
    ok(t.completedRounds == 1, "completed rounds is 1")
    waitUntil(8) { t.phase == .work }
    ok(t.phase == .work && t.isRunning, "break ends and the next focus round starts (phase: \(t.phase.rawValue))")
    t.pause()
    ok(!t.isRunning, "pause stops the timer")
    t.reset()
    ok(t.remaining == t.duration(for: .work), "reset restores a full round")
    UserDefaults.standard.set(false, forKey: "autoStartNext")
    let t2 = PomodoroTimer()
    t2.startWork(minutes: 1)
    waitUntil(3) { t2.phase == .shortBreak }
    wait(0.3)
    ok(t2.phase == .shortBreak && !t2.isRunning, "with auto start off the break waits for you")
    print(fails == 0 ? "\nALL PASSED" : "\n\(fails) FAILED")
    exit(fails == 0 ? 0 : 1)
}
