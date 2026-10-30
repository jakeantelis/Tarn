import SwiftUI

struct ContentView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    @State private var tab = 0          // 0 timer, 1 breathe, 2 sounds
    @State private var showSettings = false

    private var onBreak: Bool { timer.mode.hasTimer && timer.phase.isBreak }
    private var breakTint: some View { Color.purple.opacity(onBreak ? 0.14 : 0) }
    private var effectiveTab: Int { timer.mode.hasTimer ? tab : max(tab, 1) }

    var body: some View {
        VStack(spacing: 12) {
            if showSettings {
                SettingsTab(timer: timer, sound: sound, mode: timer.mode)
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
                case 1:
                    VStack(spacing: 10) {
                        BreathingView()
                        QuoteLine(text: Lines.breathe.0, author: Lines.breathe.1)
                    }
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
        .background(breakTint)
        .animation(.easeInOut(duration: 1.2), value: onBreak)
    }
}

enum Lines {
    static let focus = ("You cannot hope to make progress in areas where you have taken no action.", "Epictetus")
    /// Meditations 4.3, George Long translation (1862, public domain).
    static let breathe = ("Nowhere can a man retire with more quiet or more freedom from trouble than into his own soul.", "Marcus Aurelius")
    /// Our own words, so there is nothing to attribute or license.
    static let calm = [
        "Nothing to do right now. Just breathe.",
        "Let the next breath be slower than the last.",
        "You are allowed to rest.",
        "Soften your shoulders. Unclench your jaw.",
        "This moment is enough.",
    ]
}

struct QuoteLine: View {
    let text: String
    var author: String? = nil
    var body: some View {
        VStack(spacing: 2) {
            Text("\u{201C}\(text)\u{201D}")
                .font(.system(.caption, design: .serif).italic())
            if let author { Text(author).font(.caption2) }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
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
                    TimelineView(.animation(paused: !timer.isRunning)) { ctx in
                        let p = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 2 * .pi / 4)
                        Circle()
                            .stroke((timer.phase.isBreak ? Color.teal : Color.orange).opacity(timer.isRunning ? 0.10 + 0.14 * p : 0.08), lineWidth: 8 + 10 * (timer.isRunning ? p : 0))
                            .scaleEffect(1 + 0.05 * (timer.isRunning ? p : 0))
                    }
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

            HStack(spacing: 6) {
                ForEach(PomodoroTimer.focusChoices, id: \.self) { m in
                    Button("\(m)") { timer.setFocusMinutes(m) }
                        .buttonStyle(.bordered)
                        .tint(timer.focusMinutes == m ? .accentColor : .secondary)
                        .controlSize(.small)
                }
                Text("min").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])
                Button("Reset") { timer.reset() }
                Button("Skip") { timer.skip() }
            }

            if timer.phase == .work {
                QuoteLine(text: Lines.focus.0, author: Lines.focus.1)
            } else {
                QuoteLine(text: Lines.calm[timer.completedRounds % Lines.calm.count])
            }

            Text("Round \(timer.completedRounds % timer.roundsPerSet + 1) of \(timer.roundsPerSet)  ·  \(timer.completedRounds) done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MixerTab: View {
    @ObservedObject var sound: SoundEngine

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SoundPreset.all) { p in
                        Button { sound.applyPreset(p) } label: {
                            Label(p.name, systemImage: p.symbol).font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
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
            Text("Up to \(SoundEngine.maxLayers) sounds at once keeps the mix calm.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 230, alignment: .top)
    }
}

struct SettingsTab: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    let mode: Mode
    @AppStorage("breathStyle") private var breathStyle = BreathStyle.fill.rawValue
    @AppStorage("voiceGuide") private var voiceGuide = false
    @AppStorage("hideOthersWhenBreathing") private var hideOthers = true
    @AppStorage("soundEnabled") private var soundEnabled = false
    @AppStorage("soundScope") private var scopeRaw = SoundScope.always.rawValue

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { timer.objectWillChange.send(); set($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .pomodoro ? "Pomodoro settings" : "Breathe settings").font(.headline)
            if mode == .pomodoro { pomodoro } else { breathe }
        }
        .font(.callout)
    }

    private var pomodoro: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Rounds") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick a focus length on the Timer tab. Breaks scale with it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Breaks", selection: bind({ timer.breakStyle }, { timer.breakStyleRaw = $0.rawValue })) {
                        ForEach(BreakStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Start next round automatically", isOn: bind({ timer.autoStartNext }, { timer.autoStartNext = $0 }))
                    Toggle("Chime when a round ends", isOn: bind({ timer.chime }, { timer.chime = $0 }))
                }.padding(.vertical, 4)
            }
            GroupBox("Deep focus") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Pause when the Mac sleeps or locks", isOn: bind({ timer.pauseOnLock }, { timer.pauseOnLock = $0 }))
                    Toggle("Hide the menu bar countdown", isOn: bind({ timer.hideCountdown }, { timer.hideCountdown = $0 }))
                    TextField("Shortcut to run when focus starts", text: bind({ timer.focusStartShortcut }, { timer.focusStartShortcut = $0 }))
                    TextField("Shortcut to run when focus ends", text: bind({ timer.focusEndShortcut }, { timer.focusEndShortcut = $0 }))
                    Text("Name a Shortcut from the Shortcuts app, for example one that turns on a Focus mode to silence notifications. Leave blank to skip.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            GroupBox("Background sound") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Play sounds with Pomodoro", isOn: $soundEnabled)
                    if soundEnabled {
                        Picker("Play during", selection: $scopeRaw) {
                            ForEach(SoundScope.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        Text(scopeRaw == SoundScope.always.rawValue ? "Soft during work, fuller on breaks. Choose the mix on the Sounds tab." : "Choose the mix on the Sounds tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    private var breathe: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Visual") {
                Picker("Style", selection: $breathStyle) {
                    ForEach(BreathStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().padding(.vertical, 4)
            }
            GroupBox("Full screen") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hide other apps while breathing", isOn: $hideOthers)
                    Text("The Full screen button on the Breathe tab dims every screen so you can breathe. Press Esc to leave, and your apps come back.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            GroupBox("Voice") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Spoken cues (Breathe in, Hold, And out)", isOn: $voiceGuide)
                    Text("Uses your Mac's built in voice, offline. For a nicer voice, install a Premium voice in System Settings, Accessibility, Spoken Content.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            Text("Sounds for Breathe are mixed on the Sounds tab and play when you turn them on.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
