import SwiftUI

struct ContentView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    @State private var tab = 0          // 0 timer, 1 breathe, 2 sounds
    @State private var showSettings = false

    private var effectiveTab: Int { timer.mode.hasTimer ? tab : max(tab, 1) }

    var body: some View {
        VStack(spacing: 12) {
            if showSettings {
                SettingsTab(timer: timer, sound: sound)
            } else {
                Picker("", selection: Binding(get: { timer.mode }, set: { timer.setMode($0) })) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(timer.mode.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(get: { effectiveTab }, set: { tab = $0 })) {
                    if timer.mode.hasTimer { Text("Timer").tag(0) }
                    Text("Breathe").tag(1)
                    Text("Sounds").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch effectiveTab {
                case 0: TimerTab(timer: timer)
                case 1: BreathingView()
                default: MixerTab(sound: sound)
                }
            }

            HStack {
                if !showSettings {
                    Button {
                        sound.toggle()
                    } label: {
                        Label(sound.isPlaying ? "Sounds on" : "Sounds off",
                              systemImage: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
                    .buttonStyle(.borderless)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct TimerTab: View {
    @ObservedObject var timer: PomodoroTimer

    private var showBloom: Bool { timer.phase.isBreak && timer.breakStyle == .breathe }

    var body: some View {
        VStack(spacing: 14) {
            if showBloom {
                VStack(spacing: 4) {
                    BreathingView(compact: true)
                    Text("\(timer.phase.rawValue)  \(timer.clockText)")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(height: 190)
            } else {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(timer.phase.isBreak ? Color.teal : Color.orange,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: timer.progress)
                    VStack(spacing: 2) {
                        Text(timer.clockText)
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(timer.phase.rawValue)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 170, height: 170)
                .frame(height: 190)
            }

            HStack(spacing: 10) {
                Button(timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])
                Button("Reset") { timer.reset() }
                Button("Skip") { timer.skip() }
            }

            Text("\(timer.preset.rawValue)  ·  round \(timer.completedRounds % timer.roundsPerSet + 1) of \(timer.roundsPerSet)  ·  \(timer.completedRounds) done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MixerTab: View {
    @ObservedObject var sound: SoundEngine

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Soundscape.allCases) { s in
                HStack(spacing: 10) {
                    Image(systemName: s.symbol).frame(width: 20).foregroundStyle(.secondary)
                    Text(s.title).frame(width: 52, alignment: .leading)
                    Slider(value: Binding(get: { sound.levels[s] ?? 0 },
                                          set: { v in
                                              sound.setLevel(v, for: s)
                                              if v > 0 && !sound.isPlaying { sound.play() }
                                          }), in: 0...1)
                }
                .font(.callout)
            }
        }
        .frame(minHeight: 190, alignment: .top)
    }
}

struct SettingsTab: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    @AppStorage("soundEnabled") private var soundEnabled = false
    @AppStorage("voiceGuide") private var voiceGuide = false
    @AppStorage("soundScope") private var scopeRaw = SoundScope.always.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stillwater has two modes. Pomodoro runs timed focus rounds with breaks. Breathe is a calm bloom and optional ambient sound, with no timer. Use either one, or let Pomodoro breaks open into guided breathing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Pomodoro") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Rounds", selection: Binding(get: { timer.preset }, set: { timer.preset = $0 })) {
                        ForEach(Preset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(presetNote).font(.caption).foregroundStyle(.secondary)
                    if timer.preset == .custom {
                        Stepper("Focus \(timer.customWork) min", value: Binding(get: { timer.customWork }, set: { timer.objectWillChange.send(); timer.customWork = $0 }), in: 1...120)
                        Stepper("Short break \(timer.customShort) min", value: Binding(get: { timer.customShort }, set: { timer.objectWillChange.send(); timer.customShort = $0 }), in: 1...60)
                        Stepper("Long break \(timer.customLong) min", value: Binding(get: { timer.customLong }, set: { timer.objectWillChange.send(); timer.customLong = $0 }), in: 1...90)
                    }
                    Picker("Breaks", selection: Binding(get: { timer.breakStyle }, set: { timer.objectWillChange.send(); timer.breakStyleRaw = $0.rawValue })) {
                        ForEach(BreakStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Start next round automatically", isOn: Binding(get: { timer.autoStartNext }, set: { timer.objectWillChange.send(); timer.autoStartNext = $0 }))
                    Toggle("Play a chime when a round ends", isOn: Binding(get: { timer.chime }, set: { timer.objectWillChange.send(); timer.chime = $0 }))
                }
                .padding(.vertical, 4)
            }

            GroupBox("Breathing") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Spoken cues (Breathe in, Hold, And out)", isOn: $voiceGuide)
                    Text("Uses your Mac's built in voice, offline. Off by default. For a nicer voice, install a Premium voice in System Settings, Accessibility, Spoken Content.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Sound") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Play ambient sounds with Pomodoro", isOn: $soundEnabled)
                    if soundEnabled {
                        Picker("Play during", selection: $scopeRaw) {
                            ForEach(SoundScope.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                    }
                    Text("Off by default. You can still turn sounds on any time from the Sounds tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .font(.callout)
    }

    private var presetNote: String {
        switch timer.preset {
        case .classic: return "25 min focus, 5 min break, 15 min long break every 4 rounds."
        case .deep: return "50 min focus, 10 min break, 20 min long break every 3 rounds."
        case .custom: return "Set your own lengths."
        }
    }
}
