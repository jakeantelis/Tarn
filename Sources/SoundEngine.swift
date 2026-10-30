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

    static let all = [
        SoundPreset(name: "Ocean calm", symbol: "water.waves", mix: [.ocean: 0.7]),
        SoundPreset(name: "Forest morning", symbol: "tree", mix: [.forest: 0.55, .birds: 0.5, .stream: 0.3]),
        SoundPreset(name: "Dawn birds", symbol: "bird", mix: [.birds: 0.7, .forest: 0.25]),
        SoundPreset(name: "Quiet brook", symbol: "drop", mix: [.stream: 0.7, .birds: 0.2]),
    ]
}

/// Procedural, endlessly looping ambient generator. No audio files, so no licensing risk.
final class SoundGenerator: @unchecked Sendable {
    let kind: Soundscape
    var gain: Float = 0
    private var smoothGain: Float = 0
    private var trim: Float { kind == .ocean ? 0.5 : 1 }
    private let sampleRate: Double

    private var rng = SystemRandomNumberGenerator()
    private var lp1: Float = 0, lp2: Float = 0, lp3: Float = 0
    private var brown: Float = 0
    private var bp: Float = 0, bpLow: Float = 0
    private var phase: Double = 0
    private var lfo2: Double = 0
    private var swellRate: Double
    // chirps
    private var chirpT: Double = -1, chirpLen: Double = 0, chirpF0: Double = 0, chirpF1: Double = 0
    private var chirpPhase: Double = 0, chirpAmp: Float = 0, chirpsLeft = 0
    private var nextChirp: Double
    private var clock: Double = 0
    // droplets
    private var dropEnv: Float = 0, dropF: Double = 0, dropPhase: Double = 0

    init(kind: Soundscape, sampleRate: Double) {
        self.kind = kind
        self.sampleRate = sampleRate
        swellRate = 1.0 / Double.random(in: 8...11)
        nextChirp = Double.random(in: 1...4)
        phase = Double.random(in: 0..<1)
    }

    @inline(__always) private func white() -> Float { Float.random(in: -1...1, using: &rng) }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1.0 / sampleRate
        for i in 0..<frames {
            smoothGain += (gain - smoothGain) * 0.00001
            let w = white()
            var s: Float = 0
            switch kind {
            case .ocean:
                phase += swellRate * dt
                if phase > 1 { phase -= 1 }
                lfo2 += 0.037 * dt
                let swell = Float(0.5 - 0.5 * cos(2 * .pi * phase))
                let swell2 = Float(0.5 + 0.5 * sin(2 * .pi * lfo2))
                brown = (brown + 0.02 * w) / 1.02
                let cutoff = 0.02 + 0.22 * swell * (0.6 + 0.4 * swell2)
                lp1 += cutoff * (w - lp1)
                lp2 += cutoff * (lp1 - lp2)
                let foam = (w - lp1) * 0.12 * swell * swell
                s = (lp2 * 1.6 + brown * 3.0 * (0.3 + swell)) * (0.25 + 0.75 * swell) + foam
            case .stream:
                lp1 += 0.12 * (w - lp1)
                lp2 += 0.5 * (w - lp2)
                s = (lp2 - lp1) * 0.5
                // bubbling: rising sine blips
                if dropEnv < 0.001, Double.random(in: 0..<1, using: &rng) < 0.0012 {
                    dropEnv = Float.random(in: 0.04...0.14)
                    dropF = Double.random(in: 500...1100)
                }
                if dropEnv > 0.001 {
                    dropF *= 1.00018
                    dropPhase += dropF * dt
                    s += Float(sin(2 * .pi * dropPhase)) * dropEnv
                    dropEnv *= 0.9975
                }
            case .forest, .birds:
                // soft breeze bed
                brown = (brown + 0.01 * w) / 1.01
                lp1 += 0.03 * (w - lp1)
                lp2 += 0.008 * (lp1 - lp2)
                s = lp2 * 3.0 * (0.6 + 2 * abs(brown))
                // leaf rustle crackles
                if Double.random(in: 0..<1, using: &rng) < 0.00003 {
                    dropEnv = Float.random(in: 0.1...0.35)
                }
                if dropEnv > 0.001 {
                    lp3 += 0.6 * (w - lp3)
                    s += (w - lp3) * dropEnv * 0.5
                    dropEnv *= 0.9992
                }
                // bird chirps
                clock += dt
                if chirpT < 0, clock >= nextChirp {
                    chirpsLeft = chirpsLeft > 0 ? chirpsLeft : Int.random(in: 1...4)
                    chirpLen = Double.random(in: 0.06...0.16)
                    chirpF0 = Double.random(in: 2400...4200)
                    chirpF1 = chirpF0 * Double.random(in: 0.7...1.4)
                    chirpAmp = Float.random(in: 0.04...0.11)
                    chirpT = 0
                }
                if chirpT >= 0 {
                    let f = chirpF0 + (chirpF1 - chirpF0) * (chirpT / chirpLen)
                    chirpPhase += f * dt
                    let env = Float(sin(.pi * chirpT / chirpLen))
                    s += Float(sin(2 * .pi * chirpPhase)) * env * env * chirpAmp
                    chirpT += dt
                    if chirpT >= chirpLen {
                        chirpT = -1
                        chirpsLeft -= 1
                        nextChirp = clock + (chirpsLeft > 0 ? Double.random(in: 0.08...0.2)
                                                            : Double.random(in: 2.5...9))
                    }
                }
            }
            out[i] = s * trim * smoothGain
        }
    }
}

@MainActor
final class SoundEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var levels: [Soundscape: Double] = {
        var d: [Soundscape: Double] = [:]
        for s in Soundscape.allCases { d[s] = UserDefaults.standard.object(forKey: "vol_\(s.rawValue)") as? Double ?? (s == .forest ? 0.6 : 0) }
        return d
    }()

    private let engine = AVAudioEngine()
    private var generators: [Soundscape: SoundGenerator] = [:]
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

    /// Fades the sounds out after the chosen time. 0 turns it off.
    func setSleep(minutes: Int) {
        sleepMinutes = minutes
        sleepWork?.cancel()
        guard minutes > 0 else { return }
        let w = DispatchWorkItem { [weak self] in
            self?.stop()
            self?.sleepMinutes = 0
        }
        sleepWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes) * 60, execute: w)
    }
    private var built = false

    static let maxLayers = 3

    func applyPreset(_ preset: SoundPreset) {
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
        for (s, g) in generators { g.gain = isPlaying ? Float(levels[s] ?? 0) * phaseFactor : 0 }
        if isPlaying { for s in Soundscape.allCases where (levels[s] ?? 0) > 0 { ensurePlayer(s) } }
        for s in players.keys { targets[s] = isPlaying ? Float(levels[s] ?? 0) * phaseFactor : 0 }
        startFade()
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
            if abs(diff) < 0.004 { p.volume = target } else { p.volume += diff * 0.06; moving = true }
        }
        if !moving { fadeTimer?.invalidate(); fadeTimer = nil }
    }

    private func build() {
        guard !built else { return }
        built = true
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sr = format.sampleRate > 0 ? format.sampleRate : 44100
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        for s in Soundscape.allCases {
            if let url = ["wav", "caf", "m4a"].lazy.compactMap({ Bundle.main.url(forResource: s.rawValue, withExtension: $0, subdirectory: "Sounds") }).first {
                fileURLs[s] = url   // loaded on demand, so unused sounds cost no memory
                continue
            }
            let gen = SoundGenerator(kind: s, sampleRate: sr)
            generators[s] = gen
            let node = AVAudioSourceNode(format: mono) { _, _, frames, abl in
                let bufs = UnsafeMutableAudioBufferListPointer(abl)
                if let p = bufs[0].mData?.assumingMemoryBound(to: Float.self) {
                    gen.render(p, frames: Int(frames))
                }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: mono)
        }
        engine.mainMixerNode.outputVolume = 0.8
    }

    /// Called whenever the timer changes. Timer driven sound is opt in and off by default, and it only ever
    /// stops sound that it started itself, so a mix you turned on by hand is left alone.
    func sync(mode: Mode, phase: Phase, timerRunning: Bool) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "soundEnabled"), mode.hasTimer else {
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

    func toggle() { autoPlaying = false; isPlaying ? stop() : play() }

    func play() {
        build()
        applyGainsAfter(playing: true)
        if !engine.isRunning { try? engine.start() }
        for p in players.values where !p.isPlaying { p.play() }
    }

    func stop() {
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
