import AVFoundation
import SwiftUI

enum Soundscape: String, CaseIterable, Identifiable {
    case ocean, forest, birds, stream
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .birds: return "Birds"
        case .stream: return "Stream"
        }
    }
    var symbol: String {
        switch self {
        case .ocean: return "water.waves"
        case .forest: return "tree"
        case .birds: return "bird"
        case .stream: return "drop"
        }
    }
}

struct SoundPreset: Identifiable {
    let name: String
    let symbol: String
    let mix: [Soundscape: Double]
    var id: String { name }

    /// A gentle blend of forest, stream and birds. The starting mix for anyone who has not set their own,
    /// and what plays under a guided meditation when there is no mix yet.
    static let natureCalm = SoundPreset(name: "Nature calm", symbol: "leaf", mix: [.forest: 0.5, .stream: 0.35, .birds: 0.3])

    static let all = [
        natureCalm,
        SoundPreset(name: "Ocean calm", symbol: "water.waves", mix: [.ocean: 0.7]),
        SoundPreset(name: "Forest morning", symbol: "tree", mix: [.forest: 0.55, .birds: 0.5, .stream: 0.3]),
        SoundPreset(name: "Dawn birds", symbol: "bird", mix: [.birds: 0.7, .forest: 0.25]),
        SoundPreset(name: "Quiet brook", symbol: "drop", mix: [.stream: 0.7, .birds: 0.2]),
    ]
}

@MainActor
final class SoundEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var levels: [Soundscape: Double] = {
        var d: [Soundscape: Double] = [:]
        for s in Soundscape.allCases { d[s] = UserDefaults.standard.object(forKey: "vol_\(s.rawValue)") as? Double ?? (SoundPreset.natureCalm.mix[s] ?? 0) }
        return d
    }()

    private let engine = AVAudioEngine()
    private var players: [Soundscape: AVAudioPlayerNode] = [:]
    private var fileURLs: [Soundscape: URL] = [:]

    /// Reads a bundled loop into memory the first time it is needed.
    private func ensurePlayer(_ s: Soundscape) {
        guard players[s] == nil, let url = fileURLs[s],
              let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        player.volume = 0
        // Start each layer at a random point in its loop, so layers of the same length never repeat in step.
        let offset = AVAudioFramePosition(Double.random(in: 0.1...0.9) * Double(file.length))
        player.scheduleSegment(file, startingFrame: offset, frameCount: AVAudioFrameCount(file.length - offset), at: nil)
        player.scheduleBuffer(buf, at: nil, options: .loops)
        players[s] = player
        if engine.isRunning { player.play() }
    }
    private var phaseFactor: Float = 1
    private var autoPlaying = false
    private var targets: [Soundscape: Float] = [:]
    private var fadeTimer: Timer?
    @Published var sleepMinutes = 0
    private var sleepWork: DispatchWorkItem?

    /// Fades the sounds out slowly after the chosen time. 0 turns it off.
    func setSleep(minutes: Int) {
        sleepMinutes = minutes
        sleepWork?.cancel()
        guard minutes > 0 else { return }
        let w = DispatchWorkItem { [weak self] in
            self?.sleepMinutes = 0
            self?.fadeOut(over: SoundEngine.endFade)
        }
        sleepWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes) * 60, execute: w)
    }
    private var built = false

    static let maxLayers = 3

    func applyPreset(_ preset: SoundPreset) {
        UserDefaults.standard.set(preset.name, forKey: "lastPreset")
        for s in Soundscape.allCases { setLevel(preset.mix[s] ?? 0, for: s, enforceCap: false) }
        if !isPlaying { play() }
    }

    func setLevel(_ level: Double, for s: Soundscape, enforceCap: Bool = true) {
        // More than a few layers at once sounds muddy, so the quietest other layer steps aside.
        if enforceCap, level > 0 {
            let others = Soundscape.allCases.filter { $0 != s && (levels[$0] ?? 0) > 0 }
            if others.count >= Self.maxLayers, let quietest = others.min(by: { (levels[$0] ?? 0) < (levels[$1] ?? 0) }) {
                levels[quietest] = 0
                UserDefaults.standard.set(0.0, forKey: "vol_\(quietest.rawValue)")
            }
        }
        levels[s] = level
        UserDefaults.standard.set(level, forKey: "vol_\(s.rawValue)")
        applyGains()
    }

    private func applyGains() {
        if isPlaying { for s in Soundscape.allCases where (levels[s] ?? 0) > 0 { ensurePlayer(s) } }
        for s in players.keys { targets[s] = isPlaying ? Float(levels[s] ?? 0) * phaseFactor * gain * drift(s) : 0 }
        startFade()
    }

    // MARK: Natural variation

    /// Each layer swells and settles by up to 15 percent over a few minutes, on its own slow cycle, and birds
    /// wander gently between left and right. Over a long day the blend never sounds quite the same twice.
    private var driftTimer: Timer?
    private let driftStart = Date()
    private let driftShape: [Soundscape: (period: Double, phase: Double)] = {
        var d: [Soundscape: (Double, Double)] = [:]
        for s in Soundscape.allCases { d[s] = (Double.random(in: 180...420), Double.random(in: 0...(2 * .pi))) }
        return d
    }()
    private let birdPan = (period: Double.random(in: 90...160), phase: Double.random(in: 0...(2 * .pi)))

    private func drift(_ s: Soundscape) -> Float {
        guard let shape = driftShape[s] else { return 1 }
        let t = Date().timeIntervalSince(driftStart)
        return Float(1 + 0.15 * sin(2 * .pi * t / shape.period + shape.phase))
    }

    private func startDrift() {
        guard driftTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, self.slowFadeTimer == nil else { return }
                let t = Date().timeIntervalSince(self.driftStart)
                self.players[.birds]?.pan = Float(0.35 * sin(2 * .pi * t / self.birdPan.period + self.birdPan.phase))
                self.applyGains()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        driftTimer = t
    }

    // MARK: Gentle fades

    /// Gentle fades are on unless turned off in Settings; off still ramps briefly so sound never clicks.
    static var gentle: Bool { UserDefaults.standard.object(forKey: "gentleFades") as? Bool ?? true }
    nonisolated static let pauseFadeSeconds: Double = 4
    static var pauseFade: Double { gentle ? pauseFadeSeconds : 0.3 }
    static var endFade: Double { gentle ? slowFadeSeconds : 3 }

    /// Turning sound off by hand eases it out along the same soft curve as the end of a meditation.
    func pause() {
        autoPlaying = false
        if isPlaying, slowFadeTimer == nil { fadeOut(over: Self.pauseFade) } else { stop() }
    }

    /// How long the gentle fade at the end of a meditation or the sleep timer takes.
    nonisolated static let slowFadeSeconds: Double = 30

    /// Quieter under a guided meditation, so the voice stays clear.
    private var gain: Float = 1
    private var startedForMeditation = false
    private var underMeditation = false

    /// How loud nature sound plays under the voice, as a share of its normal level. 0 is silent.
    /// Set with the Nature slider in a session's mixer.
    static var meditationLevel: Double {
        get { UserDefaults.standard.object(forKey: "meditationNatureLevel") as? Double ?? 0.45 }
        set { UserDefaults.standard.set(min(1, max(0, newValue)), forKey: "meditationNatureLevel") }
    }

    /// Picks the sound under a running meditation. Sound that was off starts now and counts as started
    /// for the meditation, so it fades away afterwards like the rest.
    func setMeditationPreset(_ preset: SoundPreset) {
        if !isPlaying { startedForMeditation = true }
        if underMeditation, slowFadeTimer == nil { gain = Float(Self.meditationLevel) }
        applyPreset(preset)
    }

    /// Moves the sound under a running meditation to a new level and remembers it for next time.
    func setMeditationLevel(_ level: Double) {
        Self.meditationLevel = level
        guard underMeditation, slowFadeTimer == nil else { return }
        gain = Float(Self.meditationLevel)
        applyGains()
    }
    private var slowFadeTimer: Timer?
    private var lingerWork: DispatchWorkItem?

    /// Lowers the sound along a soft curve over `seconds`, then stops. Feels like the sound drifting away.
    func fadeOut(over seconds: Double = SoundEngine.slowFadeSeconds) {
        guard isPlaying, slowFadeTimer == nil else { return }
        let startGain = gain, steps = max(1, Int(seconds * 10))
        var i = 0
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.slowFadeTimer != nil else { return }
                i += 1
                let f = Double(min(i, steps)) / Double(steps)
                self.gain = startGain * Float((1 + cos(f * .pi)) / 2)
                self.setVolumesNow()
                guard i >= steps else { return }
                self.cancelSlowFade()
                self.stop()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        slowFadeTimer = t
    }

    /// Ends a slow fade early. The level returns to normal, or to the soft level under a meditation.
    private func cancelSlowFade() {
        guard let t = slowFadeTimer else { return }
        t.invalidate(); slowFadeTimer = nil
        gain = underMeditation ? Float(Self.meditationLevel) : 1
    }

    /// Sets each loop straight to its level, for the slow fade, which does its own easing.
    private func setVolumesNow() {
        for (s, p) in players {
            let v = isPlaying ? Float(levels[s] ?? 0) * phaseFactor * gain * drift(s) : 0
            targets[s] = v
            p.volume = v
        }
    }

    /// Plays sound softly under a guided meditation. Uses the person's own mix, or Nature calm if they have none.
    /// `startedForBreathe` counts sound Breathe turned on by itself, which a session already fades away when it ends.
    /// With `start` off nothing new begins, but sound already playing still steps back under the voice.
    func beginMeditation(startedForBreathe: Bool, start: Bool = true) {
        lingerWork?.cancel(); lingerWork = nil
        cancelSlowFade()
        underMeditation = true
        gain = Float(Self.meditationLevel)
        startedForMeditation = false
        if isPlaying { startedForMeditation = startedForBreathe; applyGains(); return }
        guard start else { return }
        if !Soundscape.allCases.contains(where: { (levels[$0] ?? 0) > 0 }) {
            for s in Soundscape.allCases { setLevel(SoundPreset.natureCalm.mix[s] ?? 0, for: s, enforceCap: false) }
        }
        startedForMeditation = true
        play()
    }

    /// After a meditation, sound that started for it stays on, still soft, for `lingerMinutes`, then drifts away
    /// with the slow fade. Sound the person had on already, or chose to keep, returns to its normal level.
    func endMeditation(lingerMinutes: Int, keep: Bool = false) {
        underMeditation = false
        guard startedForMeditation, !keep, isPlaying else {
            startedForMeditation = false
            gain = 1
            applyGains()
            return
        }
        startedForMeditation = false
        guard lingerMinutes > 0 else { fadeOut(over: Self.endFade); return }
        let w = DispatchWorkItem { [weak self] in
            self?.lingerWork = nil
            self?.fadeOut(over: SoundEngine.endFade)
        }
        lingerWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(lingerMinutes) * 60, execute: w)
    }

    /// Eases recorded loops toward their target volume, so sound fades in and out instead of clicking.
    private func startFade() {
        guard fadeTimer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fadeStep() }
        }
        RunLoop.main.add(t, forMode: .common)
        fadeTimer = t
    }

    private func fadeStep() {
        var moving = false
        for (s, p) in players {
            let target = targets[s] ?? 0
            let diff = target - p.volume
            // Rising sound comes in at a steady, gentle pace; falling sound eases away.
            if abs(diff) < 0.004 { p.volume = target }
            else if diff > 0 { p.volume += min(diff, 0.012); moving = true }
            else { p.volume += diff * 0.035; moving = true }
        }
        if !moving { fadeTimer?.invalidate(); fadeTimer = nil }
    }

    private func build() {
        guard !built else { return }
        built = true
        // Headphones unplugged or the output device changed: restart the engine so sound keeps working.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                try? self.engine.start()
                for p in self.players.values { p.play() }
            }
        }
        for s in Soundscape.allCases {
            if let url = ["wav", "caf", "m4a"].lazy.compactMap({ Bundle.main.url(forResource: s.rawValue, withExtension: $0, subdirectory: "Sounds") }).first {
                fileURLs[s] = url   // loaded on demand, so unused sounds cost no memory
                continue
            }
        }
        engine.mainMixerNode.outputVolume = 0.8
    }

    /// Called whenever the timer changes. Timer driven sound is opt in and off by default, and it only ever
    /// stops sound that it started itself, so a mix you turned on by hand is left alone.
    func sync(mode: Mode, phase: Phase, timerRunning: Bool) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "soundEnabled") else {
            if autoPlaying { autoPlaying = false; stop() }
            return
        }
        let scope = SoundScope(rawValue: d.string(forKey: "soundScope") ?? "") ?? .always
        let want: Bool
        switch scope {
        case .always: want = timerRunning
        case .focus: want = timerRunning && !phase.isBreak
        case .breaks: want = timerRunning && phase.isBreak
        }
        if want {
            let factor: Float = (scope == .always && !phase.isBreak) ? 0.4 : 1
            if factor != phaseFactor { phaseFactor = factor; applyGains() }
            if !isPlaying { autoPlaying = true; play() }
        } else if isPlaying, autoPlaying {
            autoPlaying = false
            stop()
        }
    }

    /// Pausing eases out over a few seconds along a soft curve, so it never cuts off.
    func toggle() {
        if isPlaying, slowFadeTimer == nil { pause() } else { autoPlaying = false; play() }
    }

    func play() {
        // Pressing play during a slow fade, or while sound lingers after a meditation, brings it back at its normal level.
        cancelSlowFade()
        if lingerWork != nil { lingerWork?.cancel(); lingerWork = nil; gain = 1 }
        build()
        applyGainsAfter(playing: true)
        if !engine.isRunning { try? engine.start() }
        for p in players.values where !p.isPlaying { p.play() }
        startDrift()
    }

    func stop() {
        driftTimer?.invalidate(); driftTimer = nil
        lingerWork?.cancel(); lingerWork = nil
        if slowFadeTimer != nil { cancelSlowFade() }
        sleepWork?.cancel()
        sleepWork = nil
        sleepMinutes = 0
        applyGainsAfter(playing: false)
        // let the gain ramp finish, then pause the engine to save power
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
        }
    }

    private func applyGainsAfter(playing: Bool) {
        isPlaying = playing
        applyGains()
    }
}
