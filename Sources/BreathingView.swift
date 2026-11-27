import SwiftUI

enum BreathStyle: String, CaseIterable, Identifiable {
    case bloom = "Flower", fill = "Water"
    var id: String { rawValue }
}

struct BreathPattern: Identifiable, Hashable {
    let id: String
    let name: String
    /// inhale, hold, exhale, hold (seconds)
    let steps: [Double]
    /// Gradually slows the breath over a few minutes, the way a guided meditation settles you.
    var settling = false

    static let settle = BreathPattern(id: "settle", name: "Settle", steps: [4, 0, 6, 0], settling: true)
    static let deep = BreathPattern(id: "deep", name: "Deep", steps: [6, 2, 8, 0])
    static let box = BreathPattern(id: "box", name: "Box", steps: [4, 4, 4, 4])
    static let fourSevenEight = BreathPattern(id: "478", name: "4 7 8", steps: [4, 7, 8, 0])
    static let equal = BreathPattern(id: "equal", name: "Equal", steps: [5, 0, 5, 0])
    static let resonant = BreathPattern(id: "resonant", name: "Resonant", steps: [5.5, 0, 5.5, 0])
    static let all = [settle, deep, box, fourSevenEight, equal, resonant]

    /// Warps elapsed time so the cycle stretches from 1x to 1.7x over three minutes, then holds there.
    func warped(_ t: Double) -> Double {
        guard settling else { return t }
        let k = 0.7 / 180, cap = 180.0
        if t <= cap { return log(1 + k * t) / k }
        return log(1 + k * cap) / k + (t - cap) / 1.7
    }

    var blurb: String {
        switch id {
        case "settle": return "Starts easy and slowly deepens over three minutes. A good everyday choice."
        case "deep": return "In for 6, a short pause, out for 8. A slow, full breath."
        case "box": return "In for 4, hold 4, out for 4, hold 4. Steady and even."
        case "equal": return "In for 5, out for 5, no holds. Smooth and even."
        case "resonant": return "In and out for about 5½ each, no holds. A slow, even rhythm."
        default: return "In for 4, hold for 7, out for 8. Good for winding down."
        }
    }

    var cycle: Double { steps.reduce(0, +) }

    /// Holds of 4 seconds or more get a gentle note to check with a doctor first, if needed.
    var hasLongHolds: Bool { steps[1] >= 4 || steps[3] >= 4 }
    static let holdNote = "If you have a health condition, check with your doctor before breath-hold exercises."

    /// Returns label and circle scale (0...1) at time t into the cycle.
    func state(at t: Double) -> (label: String, scale: Double) {
        let labels = ["Breathe in", "Hold", "Breathe out", "Hold"]
        var t = warped(t).truncatingRemainder(dividingBy: cycle)
        var level = 0.0
        for (i, d) in steps.enumerated() where d > 0 {
            let target: Double
            switch i {
            case 0: target = 1
            case 2: target = 0
            default: target = level
            }
            if t < d {
                let f = t / d
                let eased = (1 - cos(f * .pi)) / 2
                let s = (i == 0 || i == 2) ? level + (target - level) * eased : level
                return (labels[i], s)
            }
            t -= d
            level = target
        }
        return ("Breathe in", 0)
    }
}

struct BreathingView: View {
    var compact = false
    /// Holds the picture still, half open, with a quiet label. Used before a break has started.
    var still = false
    /// Opens the full sound mixer. Provided by the Breathe screen.
    var onMix: (() -> Void)? = nil
    @Environment(\.popoverActive) private var active
    @Environment(\.chromeVisible) private var chrome
    /// One-time line under the Breathwork | Meditation switch, until it is used or a session begins.
    @AppStorage("breatheModeTipSeen") private var modeTipSeen = false
    @AppStorage("guideMe") private var guideMe = false
    @ObservedObject private var cleared = ScreenClearer.shared
    @ObservedObject private var sound = AppModel.shared.sound
    @ObservedObject private var meditation = Meditation.shared
    @AppStorage("meditationVoice") private var voiceSetting = "soft"
    @AppStorage("breathCues") private var breathCues = BreathCueStyle.bell.rawValue
    @AppStorage("meditationCues") private var meditationCues = BreathCueStyle.off.rawValue
    @AppStorage("breathCueVolume") private var cueVolume = BreathCueStyle.defaultVolume
    @State private var cuePickerShown = false
    /// Breathe or Guided, the switch at the top of the screen.
    @AppStorage(BreatheSettings.mode) private var modeRaw = BreatheMode.breathe.rawValue
    @AppStorage(BreatheSettings.eyesClosedTipSeen) private var tipSeen = false
    /// The voice says each breath during guided breathing, with or without a sound.
    @AppStorage(BreatheSettings.spoken) private var voiceOn = false
    private var speaking: Bool { voiceOn && !guidedMode }
    @AppStorage("breatheSound") private var breatheSound = true
    @AppStorage("meditationSounds") private var soundsUnderMeditation = true
    /// Guided only when the recorded meditations are in the app.
    private var guidedMode: Bool { (modeRaw == BreatheMode.guided.rawValue && Meditation.isAvailable) || meditation.isActive }
    /// In Meditation the speaker edits the meditation's sound, otherwise the breathing one. Odd values never mean silence.
    private var cueStyle: BreathCueStyle {
        guidedMode ? BreatheSettings.meditationCue(meditationCues) : BreatheSettings.breathCue(breathCues)
    }
    private var cueBinding: Binding<String> { guidedMode ? $meditationCues : $breathCues }
    @AppStorage("meditationNatureLevel") private var natureLevel = 0.45
    /// The length of the last guided meditation, marked in the menus so it is quick to choose again.
    @AppStorage("meditationMinutes") private var lastLength = 0
    private var markedLength: Int { meditation.minutes ?? lastLength }
    @AppStorage("lastPreset") private var lastPreset = ""
    @State private var mixerShown = false
    @AppStorage("allowScreenTakeover") private var allowTakeover = true
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.bloom.rawValue
    @AppStorage("breathPattern") private var patternID = "settle"
    private var pattern: BreathPattern {
        get { BreathPattern.all.first { $0.id == patternID } ?? .settle }
        nonmutating set { patternID = newValue.id }
    }
    @State private var start = Date()
    @State private var pausedAt: TimeInterval? = nil   // elapsed seconds while paused
    @AppStorage("coachMinutes") private var coachMinutes = 0
    @State private var coachStart: Date? = nil
    @State private var coachDone = false
    @State private var burst = 0
    @State private var pausedFrom: Date? = nil
    @State private var soundWasOn = false

    /// A guided session always uses Settle, which slows the breath the way the voice does.
    private var activePattern: BreathPattern { meditation.isActive ? .settle : pattern }
    private var isPaused: Bool { meditation.isActive ? meditation.isPaused : pausedAt != nil }
    private var menuTitle: String {
        if let m = meditation.minutes { return "Meditation, \(m) min" }
        return coachMinutes == 0 ? "Options" : "\(coachMinutes) min session"
    }

    var body: some View {
        content
            .background(compact ? nil : RoundedRectangle(cornerRadius: 34)
                .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.40, blue: 0.62).opacity(0.22),
                                              Color(red: 0.25, green: 0.55, blue: 0.58).opacity(0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(-8))
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in checkCoach() }
            .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { now in cueTick(now) }
            .onDisappear { AppModel.shared.cueStop(.screen) }
            .onAppear {
                if coachMinutes > 0 && coachStart == nil && !compact { coachMinutes = 0 }
                // With the spoken cue, opening Breathe starts afresh: the breath waits while the voice names the exercise.
                if !compact && !still && !guidedMode && coachStart == nil && pausedAt == nil {
                    let lead = BreathVoice.leadIn(pattern)
                    if lead > 0 { start = Date().addingTimeInterval(lead) }
                }
            }
            // When a guided session ends the breath carries on from the start of your own rhythm.
            .onChange(of: meditation.isActive) { _, on in if !on { start = freshStart(); pausedAt = nil; pausedFrom = nil } }
            // The Nature sounds switch in the speaker picker acts at once on the Breathe screen.
            .onChange(of: breatheSound) { _, on in
                guard !compact, !guidedMode else { return }
                if on { AppModel.shared.startBreatheSound() } else if AppModel.shared.startedForBreathe { sound.pause() }
            }
    }

    /// One quiet menu for the things you set once: session length, the look, and background sound.
    private var optionsMenu: some View {
        Menu {
            if !guidedMode {
            Section("Session") {
                ForEach([0, 1, 3, 5, 10, 20], id: \.self) { m in
                    Button { setCoach(m) } label: {
                        let name = m == 0 ? "No timer" : "\(m) minutes"
                        if coachMinutes == m && !meditation.isActive { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            }
            }
            if guidedMode {
                Section("Guided meditation") {
                    let voice = Meditation.voice(preferring: voiceSetting)
                    ForEach(Meditation.lengths(voice: voice), id: \.self) { m in
                        Button { beginGuided(m) } label: {
                            let name = "\(m) minutes"
                            if markedLength == m { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                    if Meditation.voices.count > 1 {
                        Menu("Voice: \(Meditation.label(voice))") {
                            ForEach(Meditation.voices, id: \.self) { v in
                                Button { voiceSetting = v } label: {
                                    if voice == v { Label(Meditation.label(v), systemImage: "checkmark") } else { Text(Meditation.label(v)) }
                                }
                            }
                        }
                    }
                    if meditation.isActive { Button("End meditation") { endGuided() } }
                }
            }
            if !guidedMode {
            Section("Rhythm") {
                ForEach(BreathPattern.all) { pt in
                    Button {
                        pattern = pt; start = freshStart(pt)
                    } label: {
                        if patternID == pt.id { Label(pt.name, systemImage: "checkmark") } else { Text(pt.name) }
                    }
                    .disabled(meditation.isActive)
                }
            }
            }
            Section("Look") {
                ForEach(BreathStyle.allCases) { st in
                    Button { withAnimation(.easeInOut(duration: 0.4)) { styleRaw = st.rawValue } } label: {
                        if styleRaw == st.rawValue { Label(st.rawValue, systemImage: "checkmark") } else { Text(st.rawValue) }
                    }
                }
            }
            Section("Sound") {
                ForEach(SoundPreset.all) { p in
                    Button { sound.applyPreset(p) } label: { Label(p.name, systemImage: p.symbol) }
                }
                Button("Sound off") { sound.pause() }
                if let onMix { Button("Mix sounds…") { onMix() } }
            }
            Section("More") {
                if allowTakeover {
                    Button("Full screen") { BreatheOverlay.shared.show() }
                    Button(cleared.isCleared ? "Bring back hidden apps" : "Hide other apps") { cleared.isCleared ? cleared.restore() : cleared.clear() }
                }
                Button { guideMe.toggle() } label: {
                    if guideMe { Label("Gentle guide", systemImage: "checkmark") } else { Text("Gentle guide") }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                Text(menuTitle)
                if sound.isPlaying { Image(systemName: "speaker.wave.2.fill").font(.system(size: 9)) }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Session length, guided meditation, rhythm, look, sound and screen")
    }

    /// Easy to find on the Breathe screen itself: pick a length to start a guided meditation, or end the one playing.
    @ViewBuilder private var guidedButton: some View {
        if meditation.isActive {
            HStack(spacing: 8) {
                Button { mixerShown.toggle() } label: {
                    Image(systemName: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(.system(size: 11))
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(CapsuleButtonStyle(small: true))
                .help("Voice and nature sound")
                .accessibilityLabel("Voice and nature sound")
                .popover(isPresented: $mixerShown, arrowEdge: .top) { mixer }
                Button { endGuided() } label: {
                    Label("End meditation", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleButtonStyle(small: true))
            }
        } else {
            let voice = Meditation.voice(preferring: voiceSetting)
            Menu {
                Section("Guided meditation") {
                    ForEach(Meditation.lengths(voice: voice), id: \.self) { m in
                        Button { beginGuided(m) } label: {
                            if markedLength == m { Label("\(m) minutes", systemImage: "checkmark") } else { Text("\(m) minutes") }
                        }
                    }
                }
                if Meditation.voices.count > 1 {
                    Section("Voice") {
                        ForEach(Meditation.voices, id: \.self) { v in
                            Button { voiceSetting = v } label: {
                                if voice == v { Label(Meditation.label(v), systemImage: "checkmark") } else { Text(Meditation.label(v)) }
                            }
                        }
                    }
                }
            } label: {
                Label("Start a meditation", systemImage: "waveform").frame(maxWidth: .infinity)
            }
            .menuStyle(.button).buttonStyle(CapsuleButtonStyle(small: true)).menuIndicator(.hidden)
            .help("A recorded voice guides you for 5, 10 or 20 minutes, with sound softly underneath. Best with headphones and your eyes closed.")
        }
    }

    /// The meditation mixer: how loud the voice is, how loud the nature sound under it is, and which sound.
    /// Every change applies at once and is remembered. Clicking outside closes it.
    var mixer: some View {
        VStack(alignment: .leading, spacing: 10) {
            levelSlider("Voice", symbol: "waveform", value: $meditation.voiceLevel)
            levelSlider("Nature", symbol: "leaf", value: Binding(get: { natureLevel },
                                                                 set: { natureLevel = $0; sound.setMeditationLevel($0) }))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(SoundPreset.all) { p in
                    let on = sound.isPlaying && lastPreset == p.name
                    Button { sound.setMeditationPreset(p) } label: {
                        Label(p.name, systemImage: p.symbol)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(on ? Color.breatheTint.opacity(0.35) : Color.secondary.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(on ? Color.breatheTint.opacity(0.7) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    /// A small labelled volume slider for a guided session. Each one is remembered for next time.
    private func levelSlider(_ name: String, symbol: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
            Text(name).font(.caption).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
            Slider(value: value, in: 0...1).controlSize(.small)
        }
        .padding(.horizontal, 6)
        .help("\(name) volume during a guided meditation")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) volume")
    }

    /// A guided session: the voice track, Settle, and soft sound underneath. Any timed session stops first.
    private func beginGuided(_ minutes: Int) {
        modeRaw = BreatheMode.guided.rawValue
        tipSeen = true; modeTipSeen = true
        coachMinutes = 0; coachStart = nil; coachDone = false
        pausedAt = nil; pausedFrom = nil; soundWasOn = false
        meditation.begin(minutes: minutes)
        burst += 1
    }

    private func endGuided() {
        if meditation.isPaused, soundWasOn { soundWasOn = false; sound.play() }
        meditation.end(completed: false)
        start = freshStart()
    }

    /// When a new session's first breath begins: now, or after the spoken intro when the Voice cue is on.
    private func freshStart(_ p: BreathPattern? = nil) -> Date {
        Date().addingTimeInterval(guidedMode ? 0 : BreathVoice.leadIn(p ?? pattern))
    }

    private func setCoach(_ minutes: Int) {
        if meditation.isActive { endGuided() }
        coachMinutes = minutes
        coachDone = false
        start = freshStart(); pausedAt = nil
        // The spoken intro does not count toward the session.
        coachStart = minutes > 0 ? max(start, Date()) : nil
        if minutes > 0 {
            tipSeen = true; modeTipSeen = true
            burst += 1
            AppModel.shared.startBreatheSound()
        }
    }

    /// Breath cues for the Breathe screen: only while it is showing, not paused, and not just a quiet preview.
    private func cueTick(_ now: Date) {
        guard !compact, !still else { return }
        let t = meditation.isActive ? meditation.elapsed(at: now) : (pausedAt ?? now.timeIntervalSince(start))
        // In Guided the guided cue plays, even before a meditation starts, so the speaker button means one thing.
        AppModel.shared.cueTick(.screen, t: t, pattern: activePattern, guided: guidedMode, running: active, paused: isPaused)
    }

    private func checkCoach() {
        guard let cs = coachStart, coachMinutes > 0 else { return }
        let elapsed = Date().timeIntervalSince(cs), total = Double(coachMinutes * 60)
        guard elapsed >= total else { return }
        coachStart = nil
        coachDone = true
        // The ambient sound fading out is the signal that the session is over, unless the user keeps it on.
        if !UserDefaults.standard.bool(forKey: "keepSoundAfterSession") { AppModel.shared.sound.stop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { coachDone = false }
    }

    /// Pause or resume. Breathwork: the clock, the picture, the voice and breath sound (they carry on mid-sound)
    /// and the nature sound all hold. A meditation holds its voice and breath together.
    private func togglePause() {
                if meditation.isActive {
                    // The voice, the breath and the clock hold together, and the sound with them.
                    if meditation.isPaused {
                        meditation.togglePause()
                        if soundWasOn { soundWasOn = false; sound.play() }
                    } else {
                        meditation.togglePause()
                        soundWasOn = sound.isPlaying
                        if soundWasOn { sound.pause() }
                    }
                } else if let p = pausedAt {
                    // Resume: the breath, the session clock and the sound all pick up where they stopped.
                    start = Date().addingTimeInterval(-p)
                    if let at = pausedFrom, coachStart != nil { coachStart = coachStart?.addingTimeInterval(Date().timeIntervalSince(at)) }
                    pausedAt = nil; pausedFrom = nil
                    if soundWasOn { soundWasOn = false; sound.play() }
                } else {
                    // Pause: the sound stops too, so a paused session is really quiet.
                    pausedAt = Date().timeIntervalSince(start); pausedFrom = Date()
                    soundWasOn = sound.isPlaying
                    if soundWasOn { sound.pause() }
                }
    }

    /// True while the spoken cue names the exercise before the first breath. A click on the picture skips it.
    private func introPlaying(_ t: Double) -> Bool {
        !compact && !still && speaking && t < -0.7
    }

    /// Cuts the spoken intro short; the first breath starts a moment later, unhurried.
    private func skipIntro() {
        AppModel.shared.cues.stopVoice()
        start = Date().addingTimeInterval(0.6)
    }

    private var content: some View {
        VStack(spacing: 12) {
            if !compact && Meditation.isAvailable {
                Picker("Mode", selection: $modeRaw) {
                    ForEach(BreatheMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
                .accessibilityLabel("Mode")
                .onChange(of: modeRaw) { _, v in
                    modeTipSeen = true
                    // Back to Breathe ends a meditation that is playing; the breath carries on from your own rhythm.
                    if v == BreatheMode.breathe.rawValue && meditation.isActive { endGuided() }
                    // Into Meditation during the spoken intro: the intro stops and the breath starts now.
                    if v == BreatheMode.guided.rawValue && start > Date() { AppModel.shared.cues.stopVoice(); start = Date() }
                }
                .fadesWithChrome(chrome)
                if !modeTipSeen {
                    Text("Breathwork guides each breath. Meditation is a calm voice talking you through 5 to 20 minutes.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .fadesWithChrome(chrome)
                }
            }
            if !compact {
                HStack(spacing: 8) {
                    optionsMenu
                    if allowTakeover {
                        Button { tipSeen = true; BreatheOverlay.shared.show() } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(7)
                                .background(Circle().fill(Color.secondary.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .help("Full screen. Esc or a click brings you back.")
                        .accessibilityLabel("Full screen")
                    }
                    if !still {
                        Button { togglePause() } label: {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(7)
                                .background(Circle().fill(Color.secondary.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .help(isPaused ? "Resume" : "Pause. Clicking the picture does the same.")
                        .accessibilityLabel(isPaused ? "Resume" : "Pause")
                    }
                    Button { cuePickerShown.toggle(); tipSeen = true } label: {
                        Image(systemName: cueStyle == .off && !speaking ? "speaker.slash" : "speaker.wave.2")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(7)
                            .background(Circle().fill(Color.secondary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .help("Breath sounds: hear each breath with your eyes closed")
                    .accessibilityLabel("Breath sounds")
                    .accessibilityValue(speaking ? (cueStyle == .off ? "Voice" : "Voice and \(cueStyle.label)") : cueStyle.label)
                    .popover(isPresented: $cuePickerShown, arrowEdge: .bottom) {
                        BreathCueQuickPicker(selection: cueBinding, volume: $cueVolume, voice: guidedMode ? nil : $voiceOn,
                                             nature: guidedMode ? $soundsUnderMeditation : $breatheSound)
                    }
                }
                .fadesWithChrome(chrome)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active || isPaused || still)) { ctx in
                let guided = meditation.isActive && !compact && !still
                let t = still ? 2.0 : (guided ? meditation.elapsed(at: ctx.date) : (pausedAt ?? ctx.date.timeIntervalSince(start)))
                // A guided session opens with a few quiet seconds while the welcome is spoken,
                // and the spoken cue's intro gets the same quiet start.
                let settling = !compact && !still && t < 0
                let st = activePattern.state(at: max(0, t))
                let s = settling ? (label: "Get comfortable", scale: 0.0) : st
                VStack(spacing: 8) {
                ZStack {
                    RippleBurst(color: Color.breatheTint, trigger: burst).padding(10)
                    switch BreathStyle(rawValue: styleRaw) ?? .bloom {
                    case .fill: FillCanvas(scale: s.scale, time: t)
                    case .bloom: BloomCanvas(scale: s.scale, time: t)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 120 : 190)
                // With the controls out of the way, the picture grows to fill the card.
                .scaleEffect(!compact && !still && !chrome ? 1.3 : 1)
                .animation(.easeInOut(duration: 0.9), value: chrome)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !compact else { return }
                    if t < 0 && speaking && pausedAt == nil { skipIntro(); return }
                    togglePause()
                }
                .help(compact ? "" : (isPaused ? "Click to resume" : "Click to pause"))

                // The cue sits under the picture, not on top of it, so it is always easy to read.
                // A soft, lowercase cue that fades from one word to the next.
                Text((still ? "when you are ready" : (isPaused ? "Paused. Tap to resume" : s.label)).lowercased())
                    .font(.system(size: compact ? 17 : 21, weight: .light, design: .serif))
                    .tracking(1.6)
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(height: 28)
                    .id(still ? "still" : (isPaused ? "paused" : s.label))
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.9), value: s.label)
                if guided {
                    let left = max(0, Int((meditation.total - max(0, t)).rounded(.up)))
                    Text(String(format: "%d:%02d left", left / 60, left % 60))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .opacity(settling ? 0 : 1)
                    if meditation.volumeLow {
                        Label("Volume is low. Turn it up to hear the voice.", systemImage: "speaker.wave.1")
                            .font(.caption2).foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                } else if let cs = coachStart, coachMinutes > 0 {
                    let left = max(0, Double(coachMinutes * 60) - ctx.date.timeIntervalSince(cs))
                    Text(String(format: "%d:%02d left", Int(left) / 60, Int(left) % 60))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if sound.isPlaying {
                        Text("Sound is on. Change it in Options, or turn it off in Settings.")
                            .font(.caption2).foregroundStyle(.secondary.opacity(0.8)).multilineTextAlignment(.center)
                    }
                } else if introPlaying(t) {
                    Text("Intro · click the picture to skip")
                        .font(.caption).foregroundStyle(.secondary)
                } else if coachDone || (meditation.justFinished && !compact) {
                    Text("Well done. Take a moment before you go.").font(.caption).foregroundStyle(.secondary)
                }
                if !compact && (guided || meditation.justFinished) {
                    // In a guided session the line under the picture is what the voice just said.
                    Text(meditation.caption)
                        .font(.system(.caption, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                        .id(meditation.caption)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 1.2), value: meditation.caption)
                } else if guideMe && !compact {
                    Text(Guidance.line(at: t))
                        .font(.system(.caption, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(height: 30)
                        .id(Guidance.index(at: t))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 1.2), value: Guidance.index(at: t))
                }
                }
            }

            if !compact {
                if allowTakeover && !guidedMode {
                    Button { tipSeen = true; modeTipSeen = true; AppModel.shared.calmMode() } label: {
                        Label("Calm mode", systemImage: "moon.stars").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, small: true))
                    .help("Full screen, your sound mix and Hide apps in one go. Esc or a click brings you back.")
                    .fadesWithChrome(chrome)
                }
                if guidedMode {
                    guidedButton.fadesWithChrome(chrome)
                }
                // A one-time tip: once someone has opened the sound picker or started a session, they know.
                if !tipSeen, let hint = speaking ? BreathCueStyle.voiceHint : cueStyle.hint(guided: guidedMode) {
                    Text(hint)
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fadesWithChrome(chrome)
                }
            }
        }
    }
}

/// Flower bloom: soft petals open on the inhale and close on the exhale.
struct BloomCanvas: View {
    let scale: Double
    let time: Double

    private let greens: [Color] = [
        Color(red: 0.98, green: 0.80, blue: 0.84),   // outer petals, soft pink
        Color(red: 0.96, green: 0.70, blue: 0.78),
        Color(red: 0.93, green: 0.84, blue: 0.62),   // warm center
    ]

    var body: some View {
        Canvas { g, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) / 2
            // outer glow
            let glowR = base * (0.55 + 0.4 * scale)
            g.fill(Path(ellipseIn: CGRect(x: c.x - glowR, y: c.y - glowR, width: glowR * 2, height: glowR * 2)),
                   with: .radialGradient(Gradient(colors: [greens[0].opacity(0.35), greens[0].opacity(0)]),
                                         center: c, startRadius: 0, endRadius: glowR))
            // three petal rings, each rotating at a different slow speed
            for (ring, color) in greens.enumerated() {
                let petals = 5 + ring
                let spin = (reduceMotion ? 0 : time) * (0.04 + 0.025 * Double(ring)) * (ring % 2 == 0 ? 1 : -1)
                let petalR = base * (0.13 - 0.02 * Double(ring)) * (0.7 + 0.5 * scale)
                let orbit = base * (0.06 + (0.20 + 0.08 * Double(ring)) * scale)
                for k in 0..<petals {
                    let a = spin + Double(k) / Double(petals) * 2 * .pi
                    let p = CGPoint(x: c.x + cos(a) * orbit, y: c.y + sin(a) * orbit)
                    let len = petalR * 2.1, wid = petalR * 1.05
                    let petal = Path(ellipseIn: CGRect(x: -wid, y: -len, width: wid * 2, height: len * 2))
                        .applying(CGAffineTransform(rotationAngle: a - .pi / 2).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
                    g.fill(petal, with: .color(color.opacity(0.20 + 0.05 * Double(ring))))
                    g.stroke(petal, with: .color(color.opacity(0.40)), lineWidth: 0.8)
                }
            }
            // heart of the bloom
            let hr = base * (0.14 + 0.10 * scale)
            g.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)),
                   with: .radialGradient(Gradient(colors: [greens[2].opacity(0.95), greens[1].opacity(0.2)]),
                                         center: c, startRadius: 0, endRadius: hr))
        }
    }
}

/// Round vessel; water rises on the inhale and drains on the exhale.
struct FillCanvas: View {
    let scale: Double
    let time: Double

    var body: some View {
        Canvas { g, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 8
            let vessel = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let level = c.y + r - (2 * r) * (0.08 + 0.84 * scale)
            g.drawLayer { l in
                l.clip(to: vessel)
                for (i, alpha) in [0.30, 0.45].enumerated() {
                    var wave = Path()
                    let phase = time * (0.9 + 0.4 * Double(i)) + Double(i) * 1.7
                    wave.move(to: CGPoint(x: c.x - r, y: c.y + r))
                    var x = c.x - r
                    while x <= c.x + r {
                        let y = level + sin((x / 22) + phase) * (3.0 + Double(i)) 
                        wave.addLine(to: CGPoint(x: x, y: y))
                        x += 3
                    }
                    wave.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
                    wave.closeSubpath()
                    l.fill(wave, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.62, green: 0.84, blue: 0.84).opacity(alpha), Color(red: 0.42, green: 0.66, blue: 0.80).opacity(alpha + 0.05)]),
                        startPoint: CGPoint(x: c.x, y: level), endPoint: CGPoint(x: c.x, y: c.y + r)))
                }
            }
            g.stroke(vessel, with: .color(Color(red: 0.62, green: 0.84, blue: 0.84).opacity(0.45)), lineWidth: 1.5)
        }
    }
}

/// The breath sounds, chosen right from the Breathe screen. Picking one, or letting go of the volume, plays a short breath.
struct BreathCueQuickPicker: View {
    @Binding var selection: String
    @Binding var volume: Double
    /// The voice switch for guided breathing; nil under a meditation, which already has a voice.
    var voice: Binding<Bool>? = nil
    /// Nature sound underneath: your sound mix, softly.
    @Binding var nature: Bool
    private var current: BreathCueStyle { BreathCueStyle(rawValue: selection) ?? .off }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Breath sounds").font(.headline).padding(.bottom, 6)
            if let voice {
                Toggle(isOn: voice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice")
                        Text("Says breathe in, hold, and breathe out").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: voice.wrappedValue) { _, on in if on { AppModel.shared.cues.preview(current, volume: volume, spoken: true) } }
                .padding(.bottom, 6)
                Text("Sound").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(BreathCueStyle.allCases) { style in
                Button {
                    selection = style.rawValue
                    AppModel.shared.cues.preview(style, volume: volume, spoken: voice?.wrappedValue ?? false)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.label).foregroundStyle(.primary)
                            Text(style.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        if style == current { Image(systemName: "checkmark").foregroundStyle(Color.breatheTint) }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(style == current ? .isSelected : [])
            }
            if current != .off || voice?.wrappedValue == true {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: $volume, in: BreathCueStyle.volumeRange) { editing in
                        if !editing { AppModel.shared.cues.preview(current, volume: volume, spoken: voice?.wrappedValue ?? false) }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Breath sound volume")
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .padding(.top, 8)
            }
            Divider().padding(.vertical, 8)
            Toggle("Nature sounds", isOn: $nature)
                .help(voice == nil ? "Your sound mix plays softly under the voice" : "Your sound mix plays softly while you breathe")
        }
        .padding(16)
        .frame(width: 280)
    }
}
