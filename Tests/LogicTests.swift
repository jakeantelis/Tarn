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
        check(Meditation.preroll(soundsUnder: true) == 4 && Meditation.preroll(soundsUnder: false) == 1, "nature plays a few seconds before the welcome")
        let longest = Set(VoiceScript.timeline(total: 20 * 60).map(\.passage.id))
        check(VoiceScript.all.allSatisfy { longest.contains($0.id) }, "20 min: speaks every passage")

        print("Breath cues")
        let box = BreathPattern.box
        let b0 = box.cueStep(at: 0.1)!, b1 = box.cueStep(at: 4.5)!, b2 = box.cueStep(at: 8.5)!
        check(b0.kind == .inhale && b0.seconds == 4 && b1.kind == .hold && b2.kind == .exhale, "Box: inhale, hold, exhale in order")
        check(BreathPattern.settle.cueStep(at: 4.2 + 0.0)?.kind != nil && BreathPattern.settle.cueStep(at: -1) == nil, "no cue before the session starts")
        let settleP = BreathPattern.settle
        let s0 = settleP.cueStep(at: 0.01)!
        check(s0.kind == .inhale && s0.seconds > 3.5 && s0.seconds < 4.5, "Settle: first inhale lasts about 4 s of real time (\(s0.seconds))")
        var seen = Set<Int>(), lastEnd = 0.0, contiguous = true
        var tt = 0.0
        while tt < 600 {
            let c = settleP.cueStep(at: tt)!
            if seen.insert(c.index).inserted { if abs((tt - c.elapsed) - lastEnd) > 0.2 && lastEnd > 0 { contiguous = false }; lastEnd = tt - c.elapsed + c.seconds }
            tt += 0.05
        }
        check(contiguous, "Settle: each step starts where the last one ended, even as it stretches")
        check(abs(settleP.unwarped(settleP.warped(250)) - 250) < 1e-6 && abs(settleP.unwarped(settleP.warped(40)) - 40) < 1e-6, "unwarped undoes warped")
        for style in [BreathCueStyle.bell, .tone, .wash] {
            for rising in [true, false] {
                let x = BreathCues.samples(style: style, seconds: rising ? 3.5 : 4.5, rising: rising)
                let peak = x.map(abs).max() ?? 0
                let want = Int(44_100 * max(rising ? 3.5 : 4.5, style == .bell ? 3.6 : 0))
                check(x.count == want, "\(style.label) \(rising ? "in" : "out"): lasts the breath (\(x.count) samples)")
                check(peak > 0.02 && peak < 0.9, "\(style.label) \(rising ? "in" : "out"): audible and never loud (peak \(peak))")
                check(abs(x.last ?? 1) < 0.01 && x.allSatisfy { $0.isFinite }, "\(style.label) \(rising ? "in" : "out"): ends silent, no bad samples")
            }
        }
        func rms(_ x: [Float], _ a: Double, _ b: Double) -> Float {
            let seg = x[Int(a * 44_100)..<Int(b * 44_100)]
            return (seg.map { $0 * $0 }.reduce(0, +) / Float(seg.count)).squareRoot()
        }
        for style in [BreathCueStyle.tone, .wash] {
            let inn = BreathCues.samples(style: style, seconds: 6, rising: true), out = BreathCues.samples(style: style, seconds: 8, rising: false)
            check(rms(inn, 4.5, 5.5) > 1.5 * rms(inn, 0, 1), "\(style.label): swells through the in-breath")
            check(rms(out, 7, 7.9) < 0.3 * rms(out, 0.5, 1.5), "\(style.label): drains away through the out-breath")
        }
        let click = { (x: [Float]) in zip(x, x.dropFirst()).map { abs($1 - $0) }.max() ?? 1 }
        check(click(BreathCues.samples(style: .bell, seconds: 6, rising: true)) < 0.1 && click(BreathCues.samples(style: .tone, seconds: 6, rising: false)) < 0.1, "no clicks between samples")
        let bellIn = BreathCues.samples(style: .bell, seconds: 4, rising: true), bellOut = BreathCues.samples(style: .bell, seconds: 4, rising: false)
        func crossings(_ x: [Float]) -> Int { zip(x[2000..<22_000], x[2001..<22_001]).filter { ($0 < 0) != ($1 < 0) }.count }
        check(crossings(bellIn) > crossings(bellOut), "Bell: higher breathing in than out")
        check(BreathCues.samples(style: .wash, seconds: 3, rising: true) == BreathCues.samples(style: .wash, seconds: 3, rising: true), "Wash is the same every time")
        check(BreathCueStyle.bell.hint(guided: false)?.hasPrefix("Eyes closed?") == true && BreathCueStyle.off.hint(guided: true) == nil && BreathCueStyle.off.hint(guided: false) != nil, "hints follow the style, and a guided session is quiet when Off")
        check(BreathCueStyle.allCases.allSatisfy { !$0.detail.isEmpty }, "every style has a description")
        check(BreathCues.samples(style: .off, seconds: 4, rising: true).isEmpty, "Off makes no sound")
        check(BreathCues.samples(style: .tone, seconds: 99, rising: true).count == 44_100 * 30, "a breath is capped at 30 s")
        UserDefaults.standard.removeObject(forKey: "breathCues"); UserDefaults.standard.removeObject(forKey: "meditationCues"); UserDefaults.standard.removeObject(forKey: "breathCueVolume")
        check(BreathCueStyle.breathing == .bell && BreathCueStyle.meditating == .off && BreathCueStyle.volume == 0.6, "defaults: Bell, Off while guided, volume 0.6")
        UserDefaults.standard.set("nonsense", forKey: "breathCues"); UserDefaults.standard.set(9.0, forKey: "breathCueVolume")
        check(BreathCueStyle.breathing == .bell && BreathCueStyle.volume == 1, "an unknown style falls back, volume stays in range")
        UserDefaults.standard.removeObject(forKey: "breathCues"); UserDefaults.standard.removeObject(forKey: "breathCueVolume")

        print("Breath cues: Voice")
        check(BreathCueStyle.allCases == [.bell, .tone, .wash, .off], "the voice is its own switch, so the sounds stay four")
        check(BreathCueStyle.voiceHint == "Eyes closed? A calm voice tells you when to breathe in and out.", "Voice hint")
        check(BreatheMode.breathe.label == "Breathwork" && BreatheMode.guided.label == "Meditation", "mode names")
        check(BreathPattern.all.map(\.id) == ["settle", "deep", "box", "478", "equal", "resonant"], "six rhythms, Equal and Resonant last")
        check(BreathPattern.equal.steps == [5, 0, 5, 0] && BreathPattern.resonant.steps == [5.5, 0, 5.5, 0], "Equal and Resonant timings")
        check(BreathPattern.all.filter(\.hasLongHolds).map(\.id) == ["box", "478"], "the doctor note shows for Box and 4 7 8 only")
        check(BreathPattern.equal.blurb == "In for 5, out for 5, no holds. Smooth and even."
              && BreathPattern.resonant.blurb == "In and out for about 5½ each, no holds. A slow, even rhythm.", "new rhythm blurbs")
        UserDefaults.standard.removeObject(forKey: "spokenCues")
        check(!BreatheSettings.spokenOn, "the voice is off until chosen")
        UserDefaults.standard.set("spoken", forKey: "meditationCues")
        check(BreathCueStyle.meditating == .off, "an unreleased Spoken value under a meditation plays as Off")
        UserDefaults.standard.removeObject(forKey: "meditationCues")
        for p in BreathPattern.all {
            let holds = [1, 3].filter { p.steps[$0] > 0 }
            check(BreathVoice.word(for: .inhale, seconds: p.steps[0]) == "in" && BreathVoice.word(for: .exhale, seconds: p.steps[2]) == "out"
                  && holds.allSatisfy { BreathVoice.word(for: .hold, seconds: p.steps[$0]) == "hold" }, "\(p.name): full words, and a word for every hold")
        }
        check(BreathVoice.word(for: .inhale, seconds: 2) == "in-short" && BreathVoice.word(for: .exhale, seconds: 1.5) == "out-short"
              && BreathVoice.word(for: .inhale, seconds: 1) == nil && BreathVoice.word(for: .hold, seconds: 1.2) == nil, "quick steps get short words or quiet")
        check((0..<7).map(BreathVoice.take) == [1, 2, 3, 1, 2, 3, 1], "takes rotate 1, 2, 3")
        check(BreathVoice.intro(.box) == "intro-box" && BreathVoice.intro(.fourSevenEight) == "intro-478", "intro follows the rhythm")
        // Measured clip lengths (from the iPhone app's build tool) tie the timing rule to the real recordings.
        if let data = FileManager.default.contents(atPath: "Resources/Voice/Breath/lengths.json"),
           let lengths = try? JSONDecoder().decode([String: Double].self, from: data) {
            func longest(_ w: String) -> Double {
                let takes = ["soft", "warm", "male"].flatMap { v in (1...BreathVoice.takes).compactMap { lengths["\(v)-\(w)-\($0)"] } }
                return takes.count == 9 ? takes.max()! : .infinity
            }
            check(longest("in") + 1 <= BreathVoice.longWordNeeds && longest("out") + 1 <= BreathVoice.longWordNeeds
                  && longest("hold") + 0.8 <= BreathVoice.holdNeeds
                  && longest("in-short") + 0.6 <= BreathVoice.shortWordNeeds && longest("out-short") + 0.6 <= BreathVoice.shortWordNeeds,
                  "every recorded word leaves quiet in the shortest step it is used for")
            let missing = ["soft", "warm", "male"].flatMap { v in BreathVoice.clipNames.map { "\(v)-\($0)" } }
                .filter { lengths[$0] == nil || !FileManager.default.fileExists(atPath: "Resources/Voice/Breath/\($0).m4a") }
            check(missing.isEmpty, "every voice has every clip, intros included (missing: \(missing))")
            check(BreathPattern.all.allSatisfy { p in ["soft", "warm", "male"].allSatisfy { (lengths["\($0)-\(BreathVoice.intro(p))"] ?? 99) < 10 } }, "intros stay short")
        } else {
            check(false, "Resources/Voice/Breath/lengths.json is readable")
        }
        UserDefaults.standard.set(true, forKey: "spokenCues")
        check(BreathVoice.leadIn(.box) == 0, "no intro wait when the clips are not in the bundle (test binary)")
        UserDefaults.standard.removeObject(forKey: "spokenCues")
        check(BreatheSettings.introOn, "the intro is on by default")

        print("Breathe settings upgrade")
        // Someone on the iPhone's 1.2.1 who used guided meditation with a Wash cue opens on Guided, with their cue kept.
        let gu = BreatheSettings.upgrades(from: ["guidedMeditation": true, "breathCues": "tone", "meditationCues": "wash", "meditationVoice": "warm"])
        check(gu["breatheMode"] as? String == "guided" && gu["breathCues"] == nil && gu["meditationCues"] == nil
              && gu["meditationVoice"] == nil && gu["breatheSettingsVersion"] as? Int == 2, "a guided user opens on Guided, valid choices and the voice stay")
        check(BreatheSettings.upgrades(from: ["guidedMeditation": false, "breathCues": "bell"])["breatheMode"] as? String == "breathe", "a Breathe user stays on Breathe")
        check(BreatheSettings.upgrades(from: [:])["breatheMode"] as? String == "breathe", "a fresh install (and Mac 1.0) starts on Breathe")
        let odd = BreatheSettings.upgrades(from: ["breathCues": "chime", "meditationCues": "spoken"])
        check(odd["breathCues"] as? String == "bell" && odd["meditationCues"] as? String == "off" && odd["spokenCues"] == nil,
              "odd values are repaired, and the voice stays off unless chosen")
        check(BreatheSettings.breathCue("chime") == .bell && BreatheSettings.breathCue(nil) == .bell && BreatheSettings.breathCue("off") == .off
              && BreatheSettings.meditationCue("spoken") == .off && BreatheSettings.meditationCue("bell") == .bell, "unknown never means silence")
        check(BreatheSettings.upgrades(from: ["breatheSettingsVersion": 2, "breathCues": "chime"]).isEmpty
              && BreatheSettings.upgrades(from: ["breatheMode": "guided", "guidedMeditation": false])["breatheMode"] == nil, "the upgrade runs once and keeps a chosen mode")
        let suite = UserDefaults(suiteName: "tarn-upgrade-test")!
        suite.removePersistentDomain(forName: "tarn-upgrade-test")
        suite.set("voice", forKey: "breathCues")
        BreatheSettings.upgrade(suite)
        check(suite.string(forKey: "breathCues") == "bell" && suite.string(forKey: "breatheMode") == "breathe"
              && suite.integer(forKey: "breatheSettingsVersion") == 2, "the upgrade writes its values")
        suite.removePersistentDomain(forName: "tarn-upgrade-test")

        print("Move to Applications")
        check(MoveToApplications.shouldOffer(path: "/Volumes/Tarn/Tarn.app"), "offers from a disk image")
        check(MoveToApplications.shouldOffer(path: NSHomeDirectory() + "/Downloads/Tarn.app"), "offers from Downloads")
        check(!MoveToApplications.shouldOffer(path: "/Applications/Tarn.app"), "never offers from Applications")
        check(!MoveToApplications.shouldOffer(path: NSHomeDirectory() + "/Applications/Tarn.app"), "never offers from ~/Applications")
        check(!MoveToApplications.shouldOffer(path: "/Users/dev/Projects/Tarn/build/Tarn.app"), "never offers for a development build")

        print("Updates")
        let info = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any] ?? [:]
        check(info["SUFeedURL"] as? String == "https://raw.githubusercontent.com/jakeantelis/Tarn/main/appcast.xml", "feed is the appcast on GitHub")
        check((info["SUPublicEDKey"] as? String)?.count == 44, "an EdDSA public key is set")
        check(info["SUEnableAutomaticChecks"] == nil, "automatic checks are left for the person to choose")
        check(info["SUEnableSystemProfiling"] as? Bool == false, "no system profile is sent")
        check(info["SUScheduledCheckInterval"] as? Int == 604800, "checks at most once a week")
        let feed = (try? String(contentsOfFile: "appcast.xml", encoding: .utf8)) ?? ""
        check(feed.contains("sparkle:edSignature=") && feed.contains("https://github.com/jakeantelis/Tarn/releases/download/"), "appcast items are signed and point at GitHub releases")

        print("Timer")
        for k in ["mode", "focusMinutes", "soundEnabled", "customFocusMinutes", "afterRound"] { UserDefaults.standard.removeObject(forKey: k) }
        let t = PomodoroTimer()
        check(t.duration(for: .work) == 1500 && t.duration(for: .shortBreak) == 300 && t.duration(for: .longBreak) == 900, "25 min: 25/5/15")
        check(t.roundsPerSet == 4, "25 min: 4 rounds per set")
        t.setFocusMinutes(45)
        check(t.duration(for: .work) == 2700 && t.duration(for: .shortBreak) == 600 && t.roundsPerSet == 3, "45 min: 45/10, 3 rounds")
        t.setFocusMinutes(90)
        check(t.duration(for: .shortBreak) == 900 && t.duration(for: .longBreak) == 1800, "90 min: 15/30 breaks")
        t.setFocusMinutes(500)
        check(t.effectiveMinutes == 180, "custom length is clamped to 180")
        t.setFocusMinutes(0)
        check(t.effectiveMinutes == 1, "custom length is clamped to 1")
        t.customMinutes = 37
        check(t.lengthChoices == [15, 25, 37, 45, 60, 90], "a custom length shows among the presets, sorted")
        t.setFocusMinutes(37)
        check(t.duration(for: .shortBreak) == 600, "breaks still scale with a custom length")
        t.afterRoundRaw = AfterRound.stop.rawValue
        check(t.nextLine == "Stops after this round", "Stop mode says so on the Next line")
        for k in ["focusMinutes", "customFocusMinutes", "afterRound"] { UserDefaults.standard.removeObject(forKey: k) }
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
    UserDefaults.standard.set(AfterRound.stop.rawValue, forKey: "afterRound")
    UserDefaults.standard.set(true, forKey: "autoStartNext")
    let t3 = PomodoroTimer(), counted = stats.today.rounds
    t3.startWork(minutes: 1)
    waitUntil(3) { !t3.isRunning }
    wait(0.3)
    ok(t3.phase == .work && !t3.isRunning && t3.remaining == t3.duration(for: .work), "Stop: the round resets to a full focus round, no break")
    ok(t3.completedRounds == 1 && stats.today.rounds == counted + 1, "Stop: the round is counted in stats")
    UserDefaults.standard.removeObject(forKey: "afterRound")
    ok(AppIcons.resolvedKey("sage") == "sage" && AppIcons.resolvedKey("nope") == "classic" && AppIcons.resolvedKey(nil) == "classic", "a saved Dock icon that is unknown falls back to Classic")
    ok(AppIcons.all.dropFirst().allSatisfy { FileManager.default.fileExists(atPath: "Resources/Icons/\($0.key).png") }, "every Dock icon choice has its picture")
    print(fails == 0 ? "\nALL PASSED" : "\n\(fails) FAILED")
    exit(fails == 0 ? 0 : 1)
}
