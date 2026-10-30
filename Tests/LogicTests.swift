import Foundation
import AppKit

var failures = 0
func check(_ ok: @autoclosure () -> Bool, _ msg: String) {
    if ok() { print("  ok   \(msg)") } else { print("  FAIL \(msg)"); failures += 1 }
}

@main struct Tests {
    @MainActor static func main() {
        _ = NSApplication.shared
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
        check(!t.isRunning && t.mode == .breathe, "switching to Breathe stops the timer")
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
        check(m.timer.mode == .breathe && !m.timer.isRunning, "breathe")
        m.handle(URL(string: "tarn://bogus")!)
        m.handle(URL(string: "https://example.com")!)
        check(true, "unknown and foreign URLs are ignored")
        m.handle(URL(string: "tarn://stop")!)

        print("Sound mixer")
        let e = SoundEngine()
        for s in Soundscape.allCases { e.setLevel(0, for: s) }
        let order: [Soundscape] = [.ocean, .forest, .birds, .stream]
        for (i, s) in order.enumerated() { e.setLevel(0.2 + 0.1 * Double(i), for: s) }
        check(order.filter { (e.levels[$0] ?? 0) > 0 }.count == SoundEngine.maxLayers, "layer cap: only \(SoundEngine.maxLayers) at once")
        check((e.levels[.stream] ?? 0) > 0, "newest sound is kept")
        check((e.levels[.ocean] ?? 0) == 0, "quietest sound steps aside")
        check(SoundPreset.all.allSatisfy { $0.mix.filter { $0.value > 0 }.count <= SoundEngine.maxLayers }, "all presets within the cap")

        print("Bell")
        let wav = Bell.wavData(seconds: 1)
        check(wav.count == 44 + 44100 * 2, "bell WAV has a 44 byte header plus one second of 16 bit samples (\(wav.count) bytes)")
        check(String(data: wav.prefix(4), encoding: .ascii) == "RIFF", "bell WAV starts with RIFF")
        let amps = stride(from: 44, to: wav.count - 1, by: 2).map { abs(Int(Int16(littleEndian: wav.subdata(in: $0..<$0 + 2).withUnsafeBytes { $0.load(as: Int16.self) }))) }
        check((amps.max() ?? 0) < 32000 && (amps.max() ?? 0) > 3000, "bell is audible and does not clip")
        check(amps.prefix(20).max()! < amps.dropFirst(500).prefix(500).max()!, "bell fades in (no click at the start)")

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
