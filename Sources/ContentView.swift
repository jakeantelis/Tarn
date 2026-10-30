import SwiftUI
import ServiceManagement

extension Color {
    static let matcha = Color(red: 0.50, green: 0.76, blue: 0.46)
    static let amber = Color(red: 0.98, green: 0.80, blue: 0.48)
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
    private var breakTint: some View {
        let g: [Color]
        if timer.mode == .breathe { g = [Color.water.opacity(0.14), Color.water.opacity(0.04)] }
        else if onBreak { g = [Color.purple.opacity(0.20), Color.purple.opacity(0.06)] }
        else { g = [Color(red: 0.22, green: 0.42, blue: 0.30).opacity(0.30), Color(red: 0.16, green: 0.26, blue: 0.24).opacity(0.10)] }
        return LinearGradient(colors: g, startPoint: .top, endPoint: .bottom)
    }
    private var effectiveTab: Int { timer.mode.hasTimer ? (tab == 2 || tab == 3 ? tab : 0) : (tab == 2 ? 2 : 1) }

    var body: some View {
        VStack(spacing: 12) {
            if showSettings {
                ScrollView(showsIndicators: false) {
                    SettingsTab(timer: timer, sound: sound, mode: timer.mode)
                }
                .frame(maxHeight: 460)
            } else {
                PillPicker(items: Mode.allCases, selection: Binding(get: { timer.mode }, set: { timer.setMode($0) })) { $0.rawValue }

                Text(timer.mode.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PillPicker(items: timer.mode.hasTimer ? [0, 3, 2] : [1, 2],
                           selection: Binding(get: { effectiveTab }, set: { tab = $0 })) { $0 == 2 ? "Sounds" : ($0 == 3 ? "Stats" : ($0 == 0 ? "Timer" : "Breathe")) }
                    .padding(.horizontal, 30)

                switch effectiveTab {
                case 0: TimerTab(timer: timer)
                case 3: StatsTab(stats: StatsStore.shared)
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
    static let breakIdeas = [
        "Stand up and stretch your back.",
        "Look at something far away for a few breaths.",
        "Drink a glass of water.",
        "Roll your shoulders back and let them drop.",
        "Step outside for a minute if you can.",
        "Shake out your hands and wrists.",
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
        VStack(spacing: 12) {
            if !timer.phase.isBreak {
                if timer.isRunning && !timer.intention.isEmpty {
                    Text(timer.intention).font(.callout.weight(.medium)).lineLimit(1)
                } else if !timer.isRunning {
                    TextField("What are you working on?", text: Binding(get: { timer.intention }, set: { timer.objectWillChange.send(); timer.intention = $0 }))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if timer.eyeRest, ctx.date < timer.eyeRestUntil {
                    Label("Look 20 feet away for 20 seconds", systemImage: "eye")
                        .font(.caption).padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.amber.opacity(0.25)))
                }
            }
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
                        Text((timer.phase.isBreak ? timer.phase.rawValue.uppercased() : "FOCUS") + "  \(timer.completedRounds % timer.roundsPerSet + 1)/\(timer.roundsPerSet)")
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
                if !timer.isRunning { QuoteLine(text: Lines.focusQuote(round: timer.completedRounds).text, author: Lines.focusQuote(round: timer.completedRounds).author) }
            } else {
                QuoteLine(text: Lines.breakIdeas[timer.completedRounds % Lines.breakIdeas.count])
            }
        }
    }
}

struct StatsTab: View {
    @ObservedObject var stats: StatsStore

    var body: some View {
        let week = stats.week
        let top = max(1, week.map { $0.stats.minutes }.max() ?? 1)
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                stat("\(stats.today.rounds)", "rounds today")
                stat("\(stats.today.minutes)", "minutes today")
                stat("\(stats.streak)", stats.streak == 1 ? "day streak" : "day streak")
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, d in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(d.isToday ? Color.matcha : Color.matcha.opacity(0.45))
                            .frame(width: 22, height: max(6, 110 * Double(d.stats.minutes) / Double(top)))
                        Text(d.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 140, alignment: .bottom)
            Text("\(week.reduce(0) { $0 + $1.stats.rounds }) rounds this week. Saved only on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 230, alignment: .top)
    }

    private func stat(_ big: String, _ small: String) -> some View {
        VStack(spacing: 2) {
            Text(big).font(.system(size: 28, weight: .light, design: .rounded))
            Text(small).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
            HStack {
                Text("Fade out after").font(.caption).foregroundStyle(.secondary)
                PillPicker(items: [0, 15, 30, 60], selection: Binding(get: { sound.sleepMinutes }, set: { sound.setSleep(minutes: $0) })) { $0 == 0 ? "Off" : "\($0)m" }
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
            GroupBox("General") {
                Toggle("Open Stillwater at login", isOn: Binding(get: { loginOn }, set: { setLogin($0) }))
                    .padding(.vertical, 4)
            }
        }
        .font(.callout)
    }

    @State private var loginOn = SMAppService.mainApp.status == .enabled
    private func setLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        loginOn = SMAppService.mainApp.status == .enabled
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
            GroupBox("Quick starts") {
                HStack(spacing: 6) {
                    ForEach(QuickStart.all) { q in
                        Button(q.name) { q.apply(timer: timer, sound: sound) }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                }.padding(.vertical, 4)
            }
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
            DisclosureGroup("Advanced") {
              VStack(alignment: .leading, spacing: 12) {
            GroupBox("Deep focus") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Pause when the Mac sleeps or locks", isOn: bind({ timer.pauseOnLock }, { timer.pauseOnLock = $0 }))
                    Toggle("Remind me to rest my eyes every 20 minutes", isOn: bind({ timer.eyeRest }, { timer.eyeRest = $0 }))
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
              }
            }
            .padding(.vertical, 2)
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

struct QuickStart: Identifiable {
    let name: String
    let minutes: Int
    let preset: String?
    var id: String { name }
    static let all = [
        QuickStart(name: "Deep work", minutes: 90, preset: "Rainy cabin"),
        QuickStart(name: "Study", minutes: 45, preset: "Forest morning"),
        QuickStart(name: "Sprint", minutes: 15, preset: nil),
    ]

    @MainActor func apply(timer: PomodoroTimer, sound: SoundEngine) {
        timer.setFocusMinutes(minutes)
        if let preset, let p = SoundPreset.all.first(where: { $0.name == preset }) {
            UserDefaults.standard.set(true, forKey: "soundEnabled")
            sound.applyPreset(p)
        }
    }
}
