import AVFoundation
import SwiftUI

enum Soundscape: String, CaseIterable, Identifiable {
    case ocean, rain, forest, stream, wind
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ocean: return "Ocean"
        case .rain: return "Rain"
        case .forest: return "Forest"
        case .stream: return "Stream"
        case .wind: return "Wind"
        }
    }
    var symbol: String {
        switch self {
        case .ocean: return "water.waves"
        case .rain: return "cloud.rain"
        case .forest: return "bird"
        case .stream: return "drop"
        case .wind: return "wind"
        }
    }
}

/// Procedural, endlessly looping ambient generator. No audio files, so no licensing risk.
final class SoundGenerator: @unchecked Sendable {
    let kind: Soundscape
    var gain: Float = 0
    private var smoothGain: Float = 0
    private var trim: Float { kind == .ocean ? 0.5 : kind == .wind ? 0.7 : 1 }
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
            smoothGain += (gain - smoothGain) * 0.0008
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
            case .rain:
                lp1 += 0.45 * (w - lp1)
                let hiss = (lp1 - lp2) ; lp2 += 0.04 * (lp1 - lp2)
                s = hiss * 0.55
                if dropEnv < 0.001, Double.random(in: 0..<1, using: &rng) < 0.0006 {
                    dropEnv = Float.random(in: 0.05...0.25)
                    dropF = Double.random(in: 1800...4200)
                }
                if dropEnv > 0.001 {
                    dropPhase += dropF * dt
                    s += Float(sin(2 * .pi * dropPhase)) * dropEnv
                    dropEnv *= 0.9985
                }
            case .wind:
                lfo2 += (0.05 + 0.03 * Double(brown)) * dt
                brown = (brown + 0.003 * w) / 1.003
                let gust = Float(0.5 + 0.5 * sin(2 * .pi * lfo2)) * (0.6 + 4 * abs(brown))
                let f = 0.015 + 0.05 * gust
                bpLow += f * bp
                let high = w - bpLow - 0.35 * bp
                bp += f * high
                s = bp * (0.6 + 1.6 * gust)
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
            case .forest:
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
        for s in Soundscape.allCases { d[s] = UserDefaults.standard.object(forKey: "vol_\(s.rawValue)") as? Double ?? (s == .rain ? 0.6 : 0) }
        return d
    }()

    private let engine = AVAudioEngine()
    private var generators: [Soundscape: SoundGenerator] = [:]
    private var players: [Soundscape: AVAudioPlayerNode] = [:]
    private var built = false

    func setLevel(_ level: Double, for s: Soundscape) {
        levels[s] = level
        UserDefaults.standard.set(level, forKey: "vol_\(s.rawValue)")
        applyGains()
    }

    private func applyGains() {
        for (s, g) in generators { g.gain = isPlaying ? Float(levels[s] ?? 0) : 0 }
        for (s, p) in players { p.volume = isPlaying ? Float(levels[s] ?? 0) : 0 }
    }

    private func build() {
        guard !built else { return }
        built = true
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sr = format.sampleRate > 0 ? format.sampleRate : 44100
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        for s in Soundscape.allCases {
            if let url = ["wav", "caf", "m4a"].lazy.compactMap({ Bundle.main.url(forResource: s.rawValue, withExtension: $0, subdirectory: "Sounds") }).first,
               let file = try? AVAudioFile(forReading: url),
               let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
               (try? file.read(into: buf)) != nil {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
                player.scheduleBuffer(buf, at: nil, options: .loops)
                players[s] = player
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

    /// Called whenever timer state changes. Sound is opt in and off by default.
    func sync(mode: Mode, phase: Phase, timerRunning: Bool) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "soundEnabled") else { if isPlaying { stop() }; return }
        if mode == .breathe { return }   // Breathe mode is driven by the Sounds toggle
        let scope = SoundScope(rawValue: d.string(forKey: "soundScope") ?? "") ?? .always
        let want: Bool
        switch scope {
        case .always: want = timerRunning
        case .focus: want = timerRunning && !phase.isBreak
        case .breaks: want = timerRunning && phase.isBreak
        }
        if want != isPlaying { want ? play() : stop() }
    }

    func toggle() { isPlaying ? stop() : play() }

    func play() {
        build()
        applyGainsAfter(playing: true)
        if !engine.isRunning { try? engine.start() }
        for p in players.values where !p.isPlaying { p.play() }
    }

    func stop() {
        applyGainsAfter(playing: false)
        // let the gain ramp finish, then pause the engine to save power
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
        }
    }

    private func applyGainsAfter(playing: Bool) {
        isPlaying = playing
        applyGains()
    }
}
