import AVFoundation

/// Paces a breathing session by ear, so you can close your eyes and still know when to breathe in or out.
/// Wash: a soft hush that swells through the in-breath and drains away through the out-breath.
/// Tone: a warm chord that opens as you breathe in and settles lower as you breathe out.
/// Bell: a soft bell as each breath begins, higher to breathe in, lower to breathe out. Its ring blooms
/// through the in-breath and fades away over exactly the out-breath, so the sound shows how long to breathe.
/// All three last the whole breath and sit in a soft hall reverb. Holds stay silent.
/// The sounds are made in code, so there is nothing to license. They match Tarn on iPhone.
enum BreathCueStyle: String, CaseIterable, Identifiable {
    case bell, tone, wash, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bell: "Bell"
        case .tone: "Tone"
        case .wash: "Wash"
        case .off: "Off"
        }
    }
    static let defaultVolume = 0.6
    static let volumeRange = 0.1...1.0

    /// Reads a saved choice. Anything unknown means the default for that setting.
    static func saved(_ key: String, default fallback: BreathCueStyle) -> BreathCueStyle {
        UserDefaults.standard.string(forKey: key).flatMap(BreathCueStyle.init(rawValue:)) ?? fallback
    }
    /// The Breathe screen's cue, Bell unless you chose another.
    static var breathing: BreathCueStyle { saved("breathCues", default: .bell) }
    /// The cue during a guided meditation, off unless you turn it on (the voice already guides you).
    static var meditating: BreathCueStyle { saved("meditationCues", default: .off) }
    static var volume: Double {
        let v = UserDefaults.standard.object(forKey: "breathCueVolume") as? Double ?? defaultVolume
        return min(volumeRange.upperBound, max(volumeRange.lowerBound, v))
    }
}

extension BreathPattern {
    enum Step { case inhale, hold, exhale }

    /// Where a moment of a session falls: which step it is, how long that step lasts in real seconds
    /// (Settle stretches as it goes), and how far into it we are.
    struct CueStep: Equatable {
        /// Counts up through the whole session, so a change means a new step began.
        let index: Int
        let kind: Step
        let seconds: Double
        let elapsed: Double
    }

    /// Undoes `warped`: the real seconds at which a point of the pattern's own time is reached.
    func unwarped(_ w: Double) -> Double {
        guard settling else { return w }
        let k = 0.7 / 180, cap = 180.0
        let wCap = log(1 + k * cap) / k
        if w <= wCap { return (exp(k * w) - 1) / k }
        return cap + (w - wCap) * 1.7
    }

    func cueStep(at t: Double) -> CueStep? {
        guard cycle > 0, t >= 0 else { return nil }
        let w = warped(t)
        let cycleNumber = (w / cycle).rounded(.down)
        var pos = w - cycleNumber * cycle
        var start = cycleNumber * cycle
        for (i, d) in steps.enumerated() where d > 0 {
            if pos < d {
                let begin = unwarped(start), end = unwarped(start + d)
                let kind: Step = i == 0 ? .inhale : (i == 2 ? .exhale : .hold)
                return CueStep(index: Int(cycleNumber) * 4 + i, kind: kind, seconds: end - begin, elapsed: t - begin)
            }
            pos -= d
            start += d
        }
        return nil
    }
}

/// A finished cue sound, handed from the background thread that made it to the main actor that plays it.
/// The buffer is never touched again on the thread that made it.
private struct CueSound: @unchecked Sendable { let buffer: AVAudioPCMBuffer }

@MainActor
final class BreathCues {
    private let engine = AVAudioEngine()
    /// Two players take turns, so a bell's tail rings on while the next breath begins.
    private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private var turn = 0
    nonisolated private static let rate = 44_100.0
    nonisolated private static var format: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)! }
    private let bus = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private var wired = false
    private var wanted = false
    private var volume = BreathCueStyle.defaultVolume
    /// Bumped on every stop, so a sound still being made for an old session is dropped, not played late.
    private var generation = 0
    private var observer: NSObjectProtocol?

    var isRunning: Bool { engine.isRunning }

    /// `volume` runs from 0 to 1 and sets how loud the cues sit under everything else.
    func start(volume: Double) {
        wanted = true
        self.volume = volume
        if !wired {
            wired = true
            engine.attach(bus)
            engine.attach(reverb)
            reverb.loadFactoryPreset(.largeHall)
            reverb.wetDryMix = 32
            for p in players {
                engine.attach(p)
                engine.connect(p, to: bus, format: Self.format)
            }
            engine.connect(bus, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)
            // Headphones in or out, or another output device, stops the engine; start it again so the cues carry on.
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            }
        }
        engine.mainMixerNode.outputVolume = Float(min(1, max(0, volume)))
        if !engine.isRunning { try? engine.start() }
    }

    func stop() {
        generation += 1
        wanted = false
        guard wired else { return }
        players.forEach { $0.stop() }
        if engine.isRunning { engine.stop() }
    }

    /// Starts the engine again after the system stopped it, if cues are still wanted.
    private func resume() {
        guard wanted, !engine.isRunning else { return }
        try? engine.start()
    }

    /// Makes the sound off the main thread (it takes tens of milliseconds, enough to stutter the breathing animation),
    /// then plays it, unless the session was stopped meanwhile.
    private func render(_ style: BreathCueStyle, _ parts: [(seconds: Double, rising: Bool)],
                        play: @escaping @MainActor ([AVAudioPCMBuffer]) -> Void) {
        let ticket = generation
        let making = Task.detached(priority: .userInitiated) {
            parts.compactMap { Self.buffer(style: style, seconds: $0.seconds, rising: $0.rising) }
        }
        Task { @MainActor [weak self] in
            let sounds = await making.value
            guard let self, ticket == self.generation, sounds.count == parts.count else { return }
            self.start(volume: self.volume)
            guard self.engine.isRunning else { return }
            play(sounds.map(\.buffer))
        }
    }

    /// One short breath in and out, so a style can be heard before choosing it.
    func preview(_ style: BreathCueStyle, volume: Double) {
        stop()
        guard style != .off else { return }
        wanted = true
        self.volume = volume
        render(style, [(3.5, true), (4.5, false)]) { [weak self] buffers in
            guard let p = self?.players[0] else { return }
            buffers.forEach { p.scheduleBuffer($0, at: nil, options: []) }
            p.play()
        }
    }

    /// Call when the breath moves to a new step. `seconds` is how long that step lasts. Holds make no sound.
    func play(_ style: BreathCueStyle, step: BreathPattern.Step, seconds: Double, volume: Double) {
        guard style != .off, step != .hold else { return }
        self.volume = volume
        wanted = true
        render(style, [(seconds, step == .inhale)]) { [weak self] buffers in
            guard let self, let buffer = buffers.first else { return }
            let p = self.players[self.turn]
            self.turn = (self.turn + 1) % self.players.count
            p.stop()
            p.scheduleBuffer(buffer, at: nil, options: [])
            p.play()
        }
    }

    nonisolated private static func buffer(style: BreathCueStyle, seconds: Double, rising: Bool) -> CueSound? {
        let samples = Self.samples(style: style, seconds: seconds, rising: rising)
        guard !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: samples.count) }
        return CueSound(buffer: buf)
    }

    // MARK: Sounds (mono, 44.1 kHz)

    nonisolated static func samples(style: BreathCueStyle, seconds: Double, rising: Bool) -> [Float] {
        switch style {
        case .bell: bell(seconds: seconds, rising: rising)
        case .tone: tone(seconds: seconds, rising: rising)
        case .wash: wash(seconds: seconds, rising: rising)
        case .off: []
        }
    }

    /// A soft bell with a slow, gentle onset instead of a hard strike: E breathing in, C breathing out.
    /// Under the strike, the same notes keep ringing softly and follow the breath: they bloom as you breathe in
    /// and fade to nothing at the very end of the out-breath.
    nonisolated static func bell(seconds: Double, rising: Bool) -> [Float] {
        let rate = Float(BreathCues.rate)
        let breath = Float(min(30, max(1, seconds)))
        let length = max(breath, 3.6)
        let f: Float = rising ? 329.63 : 261.63
        let n = Int(rate * length)
        let partials: [(ratio: Float, amp: Float, decay: Float)] = [(1, 1, 1.9), (2, 0.14, 0.9), (3, 0.04, 0.5)]
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / rate
            let attack = pow(sin(.pi / 2 * min(1, t / 0.09)), 2)
            let tail = min(1, (length - t) / 0.4)
            var strike: Float = 0
            for p in partials { strike += p.amp * sin(2 * .pi * f * p.ratio * t) * exp(-t / p.decay) }
            // The ringing that follows the breath: the note and its octave, each a pair slightly apart so it shimmers.
            let ring = sin(2 * .pi * f * 0.999 * t) + sin(2 * .pi * f * 1.001 * t)
                + 0.18 * (sin(2 * .pi * f * 1.998 * t) + sin(2 * .pi * f * 2.002 * t))
            let follow = t < breath ? envelope(t, length: breath, rising: rising) : 0
            out[i] = (0.2 * strike + 0.065 * ring * follow) * attack * tail
        }
        return out
    }

    /// How loud a whole-breath cue is at time `t` of a breath `length` seconds long.
    /// Breathing in it swells to the top of the breath; breathing out it starts full and drains away.
    nonisolated static func envelope(_ t: Float, length: Float, rising: Bool) -> Float {
        let edge = min(0.5, length * 0.15)
        if rising {
            return pow(sin(.pi / 2 * min(1, t / max(0.01, length - edge))), 2) * min(1, (length - t) / edge)
        }
        return min(1, t / edge) * pow(1 - t / length, 1.6)
    }

    /// A soft, warm pad: pure notes, each a pair slightly out of tune so they shimmer gently, with no buzz.
    /// Breathing in it opens on a bright, lifting chord; breathing out it settles onto a lower, resting one.
    nonisolated static func tone(seconds: Double, rising: Bool) -> [Float] {
        let rate = Float(BreathCues.rate)
        let length = Float(min(30, max(1, seconds)))
        let n = Int(rate * length)
        // In: F, C, A (F major). Out: D, A, F (D minor), a step lower and calmer.
        let notes: [(f: Float, amp: Float)] = rising
            ? [(174.61, 1), (261.63, 0.7), (440.0, 0.32)]
            : [(146.83, 1), (220.0, 0.7), (349.23, 0.32)]
        let detune: [Float] = [0.9985, 1.0015]
        var phases = [Float](repeating: 0, count: notes.count * detune.count)
        let steps = notes.flatMap { note in detune.map { 2 * Float.pi * note.f * $0 / rate } }
        let amps = notes.flatMap { note in detune.map { _ in note.amp } }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / rate
            var s: Float = 0
            for k in phases.indices {
                phases[k] += steps[k]
                if phases[k] > 2 * .pi { phases[k] -= 2 * .pi }
                s += amps[k] * sin(phases[k])
            }
            out[i] = 0.12 * s * envelope(t, length: length, rising: rising)
        }
        return out
    }

    /// Soft pink noise through a moving low-pass filter: it brightens and swells on the way in,
    /// and darkens and drains away on the way out, filling the whole step.
    nonisolated static func wash(seconds: Double, rising: Bool) -> [Float] {
        let rate = Float(BreathCues.rate)
        let length = Float(min(30, max(1, seconds)))
        let n = Int(rate * length)
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, lp: Float = 0
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / rate, x = t / length
            // Pink noise (Paul Kellet's economy filter).
            let white = Float.random(in: -1...1)
            b0 = 0.99765 * b0 + white * 0.0990460
            b1 = 0.96300 * b1 + white * 0.2965164
            b2 = 0.57000 * b2 + white * 1.0526913
            let pink = (b0 + b1 + b2 + white * 0.1848) * 0.2
            let shape = rising ? x : 1 - x
            let cutoff = 250 + 1500 * shape
            lp += (1 - exp(-2 * .pi * cutoff / rate)) * (pink - lp)
            out[i] = 0.55 * lp * envelope(t, length: length, rising: rising)
        }
        return out
    }
}
