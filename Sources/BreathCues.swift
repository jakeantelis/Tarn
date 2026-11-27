import AVFoundation

/// Paces a breathing session by ear, so you can close your eyes and still know when to breathe in or out.
/// Wash: a soft hush that swells through the in-breath and drains away through the out-breath.
/// Tone: a warm chord that opens as you breathe in and settles lower as you breathe out.
/// Bell: a soft bell as each breath begins, higher to breathe in, lower to breathe out. Its ring blooms
/// through the in-breath and fades away over exactly the out-breath, so the sound shows how long to breathe.
/// All three last the whole breath and sit in a soft hall reverb. Holds stay silent.
/// The sounds are made in code, so there is nothing to license. They match Tarn on iPhone.
/// The spoken words are separate (see BreathVoice) and can play together with any of these.
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
    /// One line under the Breathe screen telling you how each breath will be marked, so closing your eyes is obvious.
    /// Under a guided meditation the voice already guides, so nothing is said unless cues were turned on there.
    func hint(guided: Bool) -> String? {
        switch self {
        case .bell: "Eyes closed? A soft bell marks each breath."
        case .tone: "Eyes closed? A warm tone rises and falls with each breath."
        case .wash: "Eyes closed? A soft wash rises and falls with each breath."
        case .off: guided ? nil : "Tap the speaker to hear each breath with your eyes closed."
        }
    }
    var detail: String {
        switch self {
        case .bell: "A soft bell at each breath, fading as you breathe out"
        case .tone: "A warm chord that rises and falls with you"
        case .wash: "A quiet hush that swells and drains away"
        case .off: "Just the picture, no sound"
        }
    }
    static let defaultVolume = 0.6
    static let volumeRange = 0.1...1.0

    /// The Breathe screen's cue, Bell unless you chose another.
    static var breathing: BreathCueStyle { BreatheSettings.breathCue(UserDefaults.standard.string(forKey: BreatheSettings.breathCues)) }
    /// The cue during a guided meditation, off unless you turn it on (the voice already guides you).
    static var meditating: BreathCueStyle { BreatheSettings.meditationCue(UserDefaults.standard.string(forKey: BreatheSettings.meditationCues)) }
    /// The tip when the voice speaks the breaths, with or without a sound.
    static let voiceHint = "Eyes closed? A calm voice tells you when to breathe in and out."
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

/// The Breathe screen's two modes, chosen with the switch at the top. Matches Tarn on iPhone.
enum BreatheMode: String, CaseIterable, Identifiable {
    /// Guided breathing: a rhythm, paced by the picture and, if chosen, the voice and a sound.
    case breathe
    /// A recorded guided meditation.
    case guided
    var id: String { rawValue }
    /// The switch and section names. Kept here, so the wording is one change.
    var label: String { self == .breathe ? "Breathwork" : "Meditation" }
}

/// Settings keys shared by the Breathe screen and Settings, and the one-time upgrade from earlier versions.
enum BreatheSettings {
    static let mode = "breatheMode"
    static let breathCues = "breathCues"
    static let meditationCues = "meditationCues"
    /// Whether a voice says "Breathe in", "Hold", "Breathe out" during guided breathing. Plays with or without a sound.
    static let spoken = "spokenCues"
    /// One voice for both the guided meditation and the spoken cue. Kept under its 1.0 name so nothing moves.
    static let voice = "meditationVoice"
    /// Whether the spoken cue names the exercise before the first breath.
    static let spokenIntro = "spokenIntro"
    /// Set once the "Eyes closed?" tip has been seen.
    static let eyesClosedTipSeen = "eyesClosedTipSeen"
    /// The iPhone app's old switch; the Mac never wrote it, but reading it keeps the rule the same everywhere.
    static let legacyGuided = "guidedMeditation"
    static let version = "breatheSettingsVersion"
    static let current = 2

    /// The cue for the Breathe mode: anything unknown (from a newer or older version) plays Bell, never silence.
    static func breathCue(_ raw: String?) -> BreathCueStyle {
        raw.flatMap(BreathCueStyle.init(rawValue:)) ?? .bell
    }

    /// The cue under a guided meditation: unknown is Off.
    static func meditationCue(_ raw: String?) -> BreathCueStyle {
        raw.flatMap(BreathCueStyle.init(rawValue:)) ?? .off
    }

    static var spokenOn: Bool { UserDefaults.standard.bool(forKey: spoken) }

    static var introOn: Bool { UserDefaults.standard.object(forKey: spokenIntro) as? Bool ?? true }

    /// The values to write so settings saved by earlier versions read correctly in this one. Empty once done.
    static func upgrades(from stored: [String: Any]) -> [String: Any] {
        guard (stored[version] as? Int ?? 0) < current else { return [:] }
        var out: [String: Any] = [version: current]
        if stored[mode] == nil {
            out[mode] = (stored[legacyGuided] as? Bool ?? false) ? BreatheMode.guided.rawValue : BreatheMode.breathe.rawValue
        }
        if let raw = stored[breathCues] as? String, breathCue(raw).rawValue != raw {
            out[breathCues] = breathCue(raw).rawValue
        }
        if let raw = stored[meditationCues] as? String, meditationCue(raw).rawValue != raw {
            out[meditationCues] = meditationCue(raw).rawValue
        }
        return out
    }

    /// Runs the upgrade on this Mac's settings. Called once at launch.
    static func upgrade(_ d: UserDefaults = .standard) {
        for (k, v) in upgrades(from: d.dictionaryRepresentation()) { d.set(v, forKey: k) }
    }
}

/// The spoken breath cue: which recorded clip to play at each change of breath, and when. Matches Tarn on iPhone.
/// The clips are short ("Breathe in", "Hold", "Breathe out", or "In" / "Out" when a step is quick) and start the
/// moment the step starts, so the voice always matches the picture at any pace. Before the first breath, a one or two
/// sentence intro names the exercise. Clips live in the app as `Voice/Breath/<voice>-<name>.m4a`.
enum BreathVoice {
    /// Every step word is recorded in this many takes, and they rotate, so a long session never repeats one sample.
    static let takes = 3
    /// Quiet after the intro before the first "Breathe in", so the session starts unhurried.
    static let afterIntro = 1.2

    /// The longest recorded words run about 1.2 s. A word is only spoken when it leaves at least a second
    /// of quiet in the step, so the voice never crowds the breath or runs into the next word.
    static let longWordNeeds = 2.6
    static let shortWordNeeds = 1.4
    static let holdNeeds = 1.8

    /// The clip name (without voice or take) for a step that lasts `seconds`, or nil to stay quiet.
    static func word(for step: BreathPattern.Step, seconds: Double) -> String? {
        switch step {
        case .inhale: seconds >= longWordNeeds ? "in" : (seconds >= shortWordNeeds ? "in-short" : nil)
        case .exhale: seconds >= longWordNeeds ? "out" : (seconds >= shortWordNeeds ? "out-short" : nil)
        case .hold: seconds >= holdNeeds ? "hold" : nil
        }
    }

    /// The take for the `count`-th time a word is spoken (counting from 0): 1, 2, 3, 1, ...
    static func take(_ count: Int) -> Int { count % takes + 1 }

    /// The intro clip for a session with this rhythm.
    static func intro(_ pattern: BreathPattern) -> String { "intro-" + pattern.id }

    /// Every clip the app uses for one voice.
    static var clipNames: [String] {
        ["in", "out", "hold", "in-short", "out-short"].flatMap { w in (1...takes).map { "\(w)-\($0)" } }
            + BreathPattern.all.map(intro)
    }

    static func url(voice: String, name: String) -> URL? {
        Bundle.main.url(forResource: "\(voice)-\(name)", withExtension: "m4a", subdirectory: "Voice/Breath")
    }

    /// Voices with spoken cues in the app, in the order Settings lists them.
    static let voices: [String] = ["soft", "warm", "male"].filter { url(voice: $0, name: "in-1") != nil }
    /// The meditation voice if it has spoken cues, else the first one that does.
    static var chosen: String {
        let v = UserDefaults.standard.string(forKey: "meditationVoice") ?? "soft"
        return voices.contains(v) ? v : (voices.first ?? "soft")
    }

    /// How long to wait before the first breath of an unguided session: the intro and a moment of quiet,
    /// or nothing when the spoken cue or its intro is off. The intro does not count toward the session.
    static func leadIn(_ pattern: BreathPattern) -> Double {
        guard BreatheSettings.spokenOn, BreatheSettings.introOn, let url = url(voice: chosen, name: intro(pattern)),
              let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate + afterIntro
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
    /// The spoken cue plays dry: a hall would smear the words.
    private let voicePlayer = AVAudioPlayerNode()
    private var voice = ""
    private var clips: [String: AVAudioPCMBuffer] = [:]
    private var said: [String: Int] = [:]
    private var duckTask: Task<Void, Never>?

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
            engine.attach(voicePlayer)
            engine.connect(voicePlayer, to: engine.mainMixerNode, format: Self.format)
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
        voicePlayer.stop()
        said = [:]
        duckTask?.cancel(); duckTask = nil
        bus.outputVolume = 1
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
    /// With `spoken`, the voice says "Breathe in" and "Breathe out" over the sound, as in a session.
    func preview(_ style: BreathCueStyle, volume: Double, spoken: Bool = false) {
        stop()
        guard style != .off || spoken else { return }
        wanted = true
        self.volume = volume
        if spoken {
            say("in-1")
            let ticket = generation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3.5))
                guard let self, ticket == self.generation else { return }
                self.say("out-1")
            }
        }
        guard style != .off else { return }
        render(style, [(3.5, true), (4.5, false)]) { [weak self] buffers in
            guard let p = self?.players[0] else { return }
            buffers.forEach { p.scheduleBuffer($0, at: nil, options: []) }
            p.play()
        }
    }

    /// Call when the breath moves to a new step. `seconds` is how long that step lasts. Holds make no sound.
    /// With `spoken`, the voice says the step too, and the sound dips under the word.
    func play(_ style: BreathCueStyle, step: BreathPattern.Step, seconds: Double, volume: Double, spoken: Bool = false) {
        self.volume = volume
        // A quick step gets a short word or none, so the voice never crowds the breath. Takes rotate.
        if spoken, let word = BreathVoice.word(for: step, seconds: seconds) {
            wanted = true
            let n = said[word, default: 0]
            said[word] = n + 1
            say("\(word)-\(BreathVoice.take(n))")
        }
        guard style != .off, step != .hold else { return }
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

    /// Speaks the intro that names this rhythm, before the session's first breath.
    func speakIntro(_ pattern: BreathPattern, volume: Double) {
        self.volume = volume
        wanted = true
        say(BreathVoice.intro(pattern))
    }

    /// Silences the spoken cue at once (the intro, when skipped).
    func stopVoice() {
        generation += 1
        voicePlayer.stop()
    }

    /// Plays one clip of the chosen voice, stopping the word before it. Clips are read off the main thread once
    /// and kept (about 1 MB a voice), and a clip that finishes reading after Stop is dropped, not spoken late.
    private func say(_ name: String) {
        let v = BreathVoice.chosen
        if v != voice { voice = v; clips = [:] }
        if let buf = clips[name] { speak(buf); return }
        let ticket = generation
        let reading = Task.detached(priority: .userInitiated) { Self.clip(voice: v, name: name) }
        Task { @MainActor [weak self] in
            guard let sound = await reading.value, let self, self.voice == v else { return }
            self.clips[name] = sound.buffer
            if ticket == self.generation { self.speak(sound.buffer) }
        }
    }

    private func speak(_ buffer: AVAudioPCMBuffer) {
        start(volume: volume)
        guard engine.isRunning else { return }
        voicePlayer.stop()
        voicePlayer.scheduleBuffer(buffer, at: nil, options: [])
        voicePlayer.play()
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        duck(for: seconds)
        AppModel.shared.sound.duck(for: seconds)
    }

    /// The breath sound sits under the words: it dips quickly as a word starts and comes back gently after.
    private func duck(for seconds: Double) {
        duckTask?.cancel()
        duckTask = Task { @MainActor [weak self] in
            for v in stride(from: 1.0, through: 0.4, by: -0.1) { self?.bus.outputVolume = Float(v); try? await Task.sleep(for: .milliseconds(25)) }
            try? await Task.sleep(for: .seconds(max(0, seconds - 0.15)))
            for v in stride(from: 0.4, through: 1.0, by: 0.05) {
                guard !Task.isCancelled else { return }
                self?.bus.outputVolume = Float(v); try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// The clips are 44.1 kHz mono, the same as the cue format, so they read straight in.
    nonisolated private static func clip(voice: String, name: String) -> CueSound? {
        guard let url = BreathVoice.url(voice: voice, name: name), let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == rate, file.processingFormat.channelCount == 1,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil else { return nil }
        return CueSound(buffer: buf)
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
        // Repeatable noise (xorshift), so every wash sounds alike and can be tested exactly.
        var seed: UInt32 = rising ? 0x9E37_79B9 : 0x85EB_CA6B
        for i in 0..<n {
            let t = Float(i) / rate, x = t / length
            // Pink noise (Paul Kellet's economy filter).
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let white = Float(seed) / Float(UInt32.max) * 2 - 1
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
