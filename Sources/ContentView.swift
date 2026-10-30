import SwiftUI

extension Color {
    static let matcha = Color(red: 0.42, green: 0.66, blue: 0.40)
    static let water = Color(red: 0.32, green: 0.64, blue: 0.78)
}

struct ContentView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    @State private var tab: Int          // 0 timer, 1 breathe, 2 sounds
    init(timer: PomodoroTimer, sound: SoundEngine, initialTab: Int = 0, startInSettings: Bool = false) {
        self.timer = timer; self.sound = sound; _tab = State(initialValue: initialTab); _showSettings = State(initialValue: startInSettings)
    }
    @State private var showSettings = false
    @AppStorage("welcomed") private var welcomed = false

    private var onBreak: Bool { timer.mode.hasTimer && timer.phase.isBreak }
    private var breakTint: some View { (timer.mode == .breathe ? Color.water.opacity(0.08) : Color.purple.opacity(onBreak ? 0.14 : 0)) }
    private var effectiveTab: Int { timer.mode.hasTimer ? (tab == 2 ? 2 : 0) : (tab == 2 ? 2 : 1) }

    var body: some View {
        VStack(spacing: 12) {
            if showSettings {
                SettingsTab(timer: timer, sound: sound, mode: timer.mode)
            } else {
                PillPicker(items: Mode.allCases, selection: Binding(get: { timer.mode }, set: { timer.setMode($0) })) { $0.rawValue }

                Text(timer.mode.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PillPicker(items: timer.mode.hasTimer ? [0, 2] : [1, 2],
                           selection: Binding(get: { effectiveTab }, set: { tab = $0 })) { $0 == 2 ? "Sounds" : ($0 == 0 ? "Timer" : "Breathe") }
                    .padding(.horizontal, 30)

                switch effectiveTab {
                case 0: TimerTab(timer: timer)
                case 1:
                    VStack(spacing: 10) {
                        BreathingView()
                        let q = Lines.calmQuote(Int(Date().timeIntervalSinceReferenceDate / 90))
                        QuoteLine(text: q.text, author: q.author)
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
        .tint(timer.mode == .breathe ? Color.water : Color.matcha)
        .animation(.easeInOut(duration: 1.2), value: onBreak)
        .animation(.easeInOut(duration: 0.6), value: timer.mode)
        .overlay { if !welcomed { Welcome { welcomed = true } } }
    }
}

typealias Quote = (text: String, author: String?)

enum Lines {
    /// Public domain translations. Check each wording against its source before release.
    static let focus: [Quote] = [
        ("You cannot hope to make progress in areas where you have taken no action.", "Epictetus"),
        ("While we are postponing, life speeds by.", "Seneca"),
        ("Begin at once to live, and count each separate day as a separate life.", "Seneca"),
        ("Difficulties strengthen the mind, as labor does the body.", "Seneca"),
    ]
    /// Calm lines for Breathe and breaks: one Stoic quote, the rest in our own words.
    static let calm: [Quote] = [
        ("We suffer more often in imagination than in reality.", "Seneca"),
        ("Nothing to do right now. Just breathe.", nil),
        ("Let the next breath be slower than the last.", nil),
        ("You are allowed to rest.", nil),
        ("Soften your shoulders. Unclench your jaw.", nil),
        ("This moment is enough.", nil),
    ]
    static func focusQuote(round: Int) -> Quote { focus[round % focus.count] }
    static func calmQuote(_ i: Int) -> Quote { calm[i % calm.count] }
}

struct Welcome: View {
    let done: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf.fill").font(.system(size: 30)).foregroundStyle(Color.matcha)
            Text("Welcome to Stillwater").font(.title3.weight(.medium))
            VStack(alignment: .leading, spacing: 10) {
                Label("**Work** runs Pomodoro rounds for work or study. Breaks open into gentle breathing.", systemImage: "timer")
                Label("**Breathe** is a calm animation any time, no timer needed.", systemImage: "wind")
                Label("**Sounds** are optional and off until you turn them on.", systemImage: "speaker.wave.2")
            }
            .font(.callout)
            .labelStyle(.titleAndIcon)
            Button("Get started", action: done)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
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
                    LensView(progress: timer.progress, running: timer.isRunning)
                    VStack(spacing: 6) {
                        Text(timer.phase.isBreak ? timer.phase.rawValue.uppercased() : "FOCUS")
                            .font(.caption.weight(.semibold))
                            .tracking(1.5)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill((timer.phase.isBreak ? Color.purple : Color.matcha).opacity(0.22)))
                            .foregroundStyle(timer.phase.isBreak ? Color.purple : Color.matcha)
                        Text(timer.clockText)
                            .font(.system(size: 46, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(timer.isRunning ? "Next: \(timer.nextLabel)" : (timer.remaining < timer.duration(for: timer.phase) ? "Paused" : "Ready"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 200)
                .frame(height: 200)
            }

            if !timer.phase.isBreak { HStack(spacing: 6) {
                ForEach(PomodoroTimer.focusChoices, id: \.self) { m in
                    Button("\(m)") { timer.setFocusMinutes(m) }
                        .buttonStyle(.plain)
                        .font(.callout.monospacedDigit())
                        .frame(width: 36, height: 36)
                        .background(Circle()
                            .fill(timer.focusMinutes == m ? Color.matcha : Color.secondary.opacity(0.15)))
                        .foregroundStyle(timer.focusMinutes == m ? Color.white : Color.primary)
                }
                Text("min").font(.caption).foregroundStyle(.secondary)
            } }

            HStack(spacing: 10) {
                Button("Reset") { timer.reset() }.buttonStyle(CapsuleButtonStyle())
                Button(timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, large: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Skip") { timer.skip() }.buttonStyle(CapsuleButtonStyle())
            }

            if timer.phase == .work {
                QuoteLine(text: Lines.focusQuote(round: timer.completedRounds).text, author: Lines.focusQuote(round: timer.completedRounds).author)
            } else {
                QuoteLine(text: Lines.calmQuote(timer.completedRounds).text, author: Lines.calmQuote(timer.completedRounds).author)
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(SoundPreset.all) { p in
                    Button { sound.applyPreset(p) } label: {
                        Label(p.name, systemImage: p.symbol)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleButtonStyle())
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
    @AppStorage("guideMe") private var guideMe = false
    @AppStorage("hideOthersWhenBreathing") private var hideOthers = true
    @AppStorage("soundEnabled") private var soundEnabled = false
    @AppStorage("soundScope") private var scopeRaw = SoundScope.always.rawValue

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { timer.objectWillChange.send(); set($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .pomodoro ? "Work settings" : "Breathe settings").font(.headline)
            if mode == .pomodoro { pomodoro } else { breathe }
        }
        .font(.callout)
    }

    private func minutesBinding(_ key: ReferenceWritableKeyPath<PomodoroTimer, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: timer[keyPath: key] / 60, minute: timer[keyPath: key] % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            timer.objectWillChange.send()
            timer[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
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
                    Toggle("Fill the screen with breathing on breaks", isOn: bind({ timer.fullScreenBreaks }, { timer.fullScreenBreaks = $0 }))
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
            GroupBox("Schedule") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Start work automatically on a schedule", isOn: bind({ timer.scheduleEnabled }, { timer.scheduleEnabled = $0 }))
                    if timer.scheduleEnabled {
                        HStack {
                            DatePicker("From", selection: minutesBinding(\.scheduleStart), displayedComponents: .hourAndMinute)
                            DatePicker("to", selection: minutesBinding(\.scheduleEnd), displayedComponents: .hourAndMinute)
                        }
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { d in
                                let on = timer.scheduleDays & (1 << d) != 0
                                Button(["S", "M", "T", "W", "T", "F", "S"][d]) {
                                    timer.objectWillChange.send()
                                    timer.scheduleDays ^= (1 << d)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(on ? Color.matcha : Color.secondary.opacity(0.15)))
                                .foregroundStyle(on ? Color.white : Color.primary)
                            }
                        }
                        Text("Rounds and breaks then run on their own between these times, on the days you pick. The app needs to be open.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 4)
            }
            GroupBox("Background sound") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Play sounds while working", isOn: $soundEnabled)
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
                PillPicker(items: BreathStyle.allCases.map(\.rawValue), selection: $breathStyle) { $0 }
                    .padding(.vertical, 4)
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
                    Toggle("Guide me with gentle prompts", isOn: $guideMe)
                    Text("Uses your Mac's built in voice, offline. For a nicer voice, install a Premium voice in System Settings, Accessibility, Spoken Content.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            Text("Sounds for Breathe are mixed on the Sounds tab and play when you turn them on.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
