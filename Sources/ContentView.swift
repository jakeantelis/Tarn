import SwiftUI
import ServiceManagement

extension Color {
    static let onTint = Color(red: 0.13, green: 0.11, blue: 0.09)
    static var focusTint: Color { FocusPalette.current.tint }
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
    @State private var showHelp = false
    @State private var fullScreenOfferDismissed = false
    @AppStorage("offerFullScreen") private var offerFullScreen = true
    @State private var popoverActive = true
    @AppStorage("welcomed") private var welcomed = false
    @AppStorage("eveningWarmth") private var eveningWarmth = false   // re-renders the colors when changed
    @AppStorage("focusPalette") private var paletteKey = "red"

    private var onBreak: Bool { timer.mode.hasTimer && timer.phase.isBreak }
    private var breakTint: some View {
        let g: [Color]
        if timer.mode == .breathe { g = [Color.breatheTint.opacity(0.14), Color.breatheTint.opacity(0.04)] }
        else if onBreak { g = [Color.purple.opacity(0.16), Color.purple.opacity(0.04)] }
        else { g = [Color.white.opacity(0.05), Color.white.opacity(0.0)] }
        return LinearGradient(colors: g, startPoint: .top, endPoint: .bottom)
    }
    private var effectiveTab: Int { timer.mode.hasTimer ? (tab == 2 || tab == 3 ? tab : 0) : (tab == 2 ? 2 : 1) }

    var body: some View {
        VStack(spacing: 12) {
            if showHelp {
                ScrollView { HelpTab() }.frame(maxHeight: 460)
            } else if showSettings {
                ScrollView {
                    SettingsTab(timer: timer, sound: sound, mode: timer.mode, onHelp: { showHelp = true })
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
                        if sound.isPlaying && offerFullScreen && !fullScreenOfferDismissed {
                            HStack(spacing: 8) {
                                Text("Sounds are on. Go full screen?").font(.caption)
                                Spacer(minLength: 0)
                                Button("Full screen") { BreatheOverlay.shared.show(); fullScreenOfferDismissed = true }
                                    .buttonStyle(CapsuleButtonStyle(prominent: true, small: true))
                                Button("Not now") { fullScreenOfferDismissed = true }
                                    .buttonStyle(CapsuleButtonStyle(small: true))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                            .transition(.opacity)
                        }
                        BreathingView()
                        let q = Lines.calmQuote(Int(Date().timeIntervalSinceReferenceDate / 90))
                        QuoteLine(text: q.text, author: q.author)
                    }
                default: MixerTab(sound: sound)
                }
            }

            HStack {
                if !showSettings && !showHelp {
                    Button {
                        sound.toggle()
                    } label: {
                        Label(sound.isPlaying ? "Sounds on" : "Sounds off",
                              systemImage: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                Button(showSettings || showHelp ? "Done" : "Settings") { if showHelp { showHelp = false } else { showSettings.toggle() } }
                    .buttonStyle(.borderless)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
        .background(PopoverVisibilityReader(active: $popoverActive))
        .environment(\.popoverActive, popoverActive)
        .onChange(of: sound.isPlaying) { _, playing in if !playing { fullScreenOfferDismissed = false } }
        .background(breakTint)
        .tint(timer.mode == .breathe ? Color.breatheTint : FocusPalette.all[paletteKey]?.tint ?? Color.focusTint)
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
            Image(systemName: "leaf.fill").font(.system(size: 30)).foregroundStyle(Color.focusTint)
            Text("Welcome to Tarn").font(.title3.weight(.medium))
            Text("A tarn is a small, still mountain lake.")
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label("**Focus** runs Pomodoro rounds for work or study. Breaks open into gentle breathing.", systemImage: "timer")
                Label("**Breathe** is a calm animation any time, no timer needed.", systemImage: "wind")
                Label("**Sounds** are optional and off until you turn them on.", systemImage: "speaker.wave.2")
                Label("Everything is yours to set up in **Settings**.", systemImage: "slider.horizontal.3")
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

    @AppStorage("tapToStart") private var tapToStart = true
    @State private var hoveringLens = false

    /// The line under the countdown. It always says what a click will do when that matters.
    private var lensHint: String {
        guard tapToStart else { return timer.isRunning ? "Next: \(timer.nextLabel)" : "Ready" }
        if timer.isRunning { return hoveringLens ? "Click to pause" : "Next: \(timer.nextLabel)" }
        return timer.remaining < timer.duration(for: timer.phase) ? "Paused. Click to resume" : "Click to start"
    }

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
                    Label("Rest your eyes. Look far away for 20 seconds.", systemImage: "eye")
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
                        Text(timer.phase.isBreak ? timer.phase.rawValue.uppercased() : "FOCUS  \u{B7}  \(timer.completedRounds % timer.roundsPerSet + 1) of \(timer.roundsPerSet)")
                            .font(.caption.weight(.semibold))
                            .tracking(1.5)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill((timer.phase.isBreak ? Color.purple : Color.focusTint).opacity(0.22)))
                            .foregroundStyle(timer.phase.isBreak ? Color.purple : Color.focusTint)
                        Text(timer.clockText)
                            .font(.system(size: 46, weight: .light, design: .rounded))
                            .monospacedDigit()
                        HStack(spacing: 4) {
                            if tapToStart {
                                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill").font(.system(size: 8))
                            }
                            Text(lensHint)
                        }
                        .font(.caption)
                        .foregroundStyle(timer.isRunning && !hoveringLens ? Color.secondary : Color.primary.opacity(0.85))
                    }
                }
                .frame(width: 200, height: 200)
                .contentShape(Circle())
                .scaleEffect(hoveringLens && tapToStart ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: hoveringLens)
                .onHover { inside in
                    hoveringLens = inside
                    if tapToStart { if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
                .onTapGesture { if tapToStart { timer.toggle() } }
                .help(tapToStart ? (timer.isRunning ? "Click the circle to pause" : "Click the circle to start") : "")
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(timer.isRunning ? "Pauses the timer" : "Starts the timer")
                .frame(height: 200)
            }

            if !timer.phase.isBreak {
                Menu {
                    ForEach(PomodoroTimer.focusChoices, id: \.self) { m in
                        Button { timer.setFocusMinutes(m) } label: {
                            if timer.effectiveMinutes == m { Label("\(m) minutes", systemImage: "checkmark") } else { Text("\(m) minutes") }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                        Text("\(timer.effectiveMinutes) min")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Length of one focus round")
            }

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
                            .fill(d.isToday ? Color.focusTint : Color.focusTint.opacity(0.45))
                            .frame(width: 22, height: max(6, 110 * Double(d.stats.minutes) / Double(top)))
                        Text(d.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 140, alignment: .bottom)
            if let note = streakNote {
                Label(note, systemImage: "leaf.fill")
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.focusTint.opacity(0.18)))
            }
            Text("\(week.reduce(0) { $0 + $1.stats.rounds }) rounds this week. Saved only on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 230, alignment: .top)
    }

    /// A gentle note at a few milestones, never a nag.
    private var streakNote: String? {
        switch stats.streak {
        case 3...6: return "\(stats.streak) days in a row. Nice and steady."
        case 7...13: return "A week of showing up. Well done."
        case 14...29: return "\(stats.streak) days. A calm habit is forming."
        case 30...: return "\(stats.streak) days. Quietly impressive."
        default: return nil
        }
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
    var onHelp: () -> Void = {}
    @AppStorage("offerFullScreen") private var offerFullScreen = true
    @AppStorage("breathStyle") private var breathStyle = BreathStyle.bloom.rawValue
    @AppStorage("focusPalette") private var paletteKey = "red"
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("calmStartShortcut") private var calmStart = ""
    @AppStorage("calmEndShortcut") private var calmEnd = ""
    @AppStorage("eveningWarmth") private var eveningWarmth = false
    @AppStorage("keepSoundAfterSession") private var keepSound = false
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
            Text(mode == .pomodoro ? "Focus settings" : "Breathe settings").font(.headline)
            Text("Set Tarn up your way. Every option here is optional, and nothing hides your apps or fills your screen unless you ask it to.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if mode == .pomodoro { pomodoro } else { breathe }
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open Tarn at login", isOn: Binding(get: { loginOn }, set: { setLogin($0) }))
                    Toggle("Show Tarn in the Dock", isOn: $showInDock)
                        .onChange(of: showInDock) { _, _ in WindowOpener.applyDockPolicy() }
                    HStack(spacing: 6) {
                        Button("Open in a window") { WindowOpener.shared.show() }
                            .buttonStyle(CapsuleButtonStyle(small: true))
                        Button("How it works") { onHelp() }
                            .buttonStyle(CapsuleButtonStyle(small: true))
                    }
                    Text("If the menu bar icon is hard to find, a window works the same way.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            GroupBox("About") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tarn \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.callout.weight(.medium))
                    Text("A tarn is a small, still mountain lake. Tarn is a calm place to focus, and to breathe.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Free and open source, made by Antelis Labs. No account and no tracking. The recorded sounds are public domain (CC0) from BigSoundBank.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
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
            GroupBox("Theme") {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 10) {
                        ForEach(FocusPalette.order, id: \.self) { key in
                            let pal = FocusPalette.all[key]!
                            Button {
                                paletteKey = key
                                timer.objectWillChange.send()
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle().fill(LinearGradient(colors: [pal.tint.opacity(0.28), Color.black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                                        Circle().stroke(pal.tint, lineWidth: 3).padding(5)
                                        Circle().fill(pal.glow.opacity(0.85)).frame(width: 10, height: 10)
                                    }
                                    .frame(width: 38, height: 38)
                                    .overlay(Circle().stroke(Color.primary.opacity(paletteKey == key ? 0.9 : 0), lineWidth: 2).padding(-3))
                                    Text(pal.name).font(.caption2).foregroundStyle(paletteKey == key ? Color.primary : Color.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Colors for Focus. Breathe stays soft blue in every theme.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
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
                    Toggle("Fill the screen on breaks (off lets you watch or read)", isOn: bind({ timer.fullScreenBreaks }, { timer.fullScreenBreaks = $0 }))
                    Toggle("Click the circle to start and pause", isOn: Binding(get: { UserDefaults.standard.object(forKey: "tapToStart") as? Bool ?? true }, set: { timer.objectWillChange.send(); UserDefaults.standard.set($0, forKey: "tapToStart") }))
                    Toggle("Gentle reminder when a round ends", isOn: bind({ timer.roundReminder }, { timer.roundReminder = $0; if $0 { Notifier.requestPermission() } }))
                }.padding(.vertical, 4)
            }
            DisclosureGroup("Advanced") {
              VStack(alignment: .leading, spacing: 12) {
            GroupBox("Deep focus") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Pause when the Mac sleeps or locks", isOn: bind({ timer.pauseOnLock }, { timer.pauseOnLock = $0 }))
                    Toggle("Remind me to rest my eyes every 20 minutes", isOn: bind({ timer.eyeRest }, { timer.eyeRest = $0 }))
                    Toggle("Hide the menu bar countdown", isOn: bind({ timer.hideCountdown }, { timer.hideCountdown = $0 }))
                    TextField("Shortcut when focus starts", text: bind({ timer.focusStartShortcut }, { timer.focusStartShortcut = $0 }))
                    TextField("Shortcut when focus ends", text: bind({ timer.focusEndShortcut }, { timer.focusEndShortcut = $0 }))
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
                                .background(Circle().fill(on ? Color.focusTint : Color.secondary.opacity(0.15)))
                                .foregroundStyle(on ? Color.onTint : Color.primary)
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
                    Toggle("Play sounds while focusing", isOn: $soundEnabled)
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
            GroupBox("Calm mode") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Shortcut when Calm starts", text: $calmStart)
                    TextField("Shortcut when Calm ends", text: $calmEnd)
                    HStack(spacing: 6) {
                        Button("Use suggested names") { calmStart = "Tarn Calm On"; calmEnd = "Tarn Calm Off" }
                            .buttonStyle(CapsuleButtonStyle(small: true))
                        Button("Open Shortcuts") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(CapsuleButtonStyle(small: true))
                    }
                    Text("To silence notifications, make two Shortcuts with the Set Focus action: one that turns Do Not Disturb on and one that turns it off. Leave these blank to skip.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Warmer colors in the evening", isOn: $eveningWarmth)
                    Toggle("Keep sound playing after a session ends", isOn: $keepSound)

                }.padding(.vertical, 4)
            }
            GroupBox("Full screen") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Offer full screen when sounds start", isOn: $offerFullScreen)
                    Toggle("Hide other apps in full screen", isOn: $hideOthers)
                    Text("The Full screen button on the Breathe tab dims every screen so you can breathe. Click anywhere or press Esc to return, and your apps come back.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            GroupBox("Voice") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Spoken cues (breathe in, hold, breathe out)", isOn: $voiceGuide)
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
        QuickStart(name: "Deep work", minutes: 90, preset: "Quiet brook"),
        QuickStart(name: "Study", minutes: 45, preset: "Forest morning"),
        QuickStart(name: "Sprint", minutes: 15, preset: nil),
    ]

    @MainActor func apply(timer: PomodoroTimer, sound: SoundEngine) {
        // Starts the round straight away. Sound only joins in if the user has already allowed it.
        timer.startWork(minutes: minutes)
        if UserDefaults.standard.bool(forKey: "soundEnabled"),
           let preset, let p = SoundPreset.all.first(where: { $0.name == preset }) {
            sound.applyPreset(p)
        }
    }
}

/// Focus colors. Each has a tint, a soft window wash and a glow for the lens.
struct FocusPalette {
    let name: String
    let tint: Color
    let glow: Color
    let washTop: Color
    let washBottom: Color

    static let order = ["red", "coral", "teal", "amber", "graphite", "indigo", "pink", "orange", "mint", "purple"]
    static let all: [String: FocusPalette] = [
        "red": FocusPalette(name: "Tomato", tint: Color(red: 1.0, green: 0.38, blue: 0.30), glow: Color(red: 1.0, green: 0.76, blue: 0.68), washTop: Color(red: 0.46, green: 0.12, blue: 0.14), washBottom: Color(red: 0.22, green: 0.12, blue: 0.15)),
        "coral": FocusPalette(name: "Coral", tint: Color(red: 1.0, green: 0.55, blue: 0.45), glow: Color(red: 1.0, green: 0.82, blue: 0.72), washTop: Color(red: 0.46, green: 0.20, blue: 0.20), washBottom: Color(red: 0.24, green: 0.14, blue: 0.18)),
        "teal": FocusPalette(name: "Teal", tint: Color(red: 0.20, green: 0.80, blue: 0.72), glow: Color(red: 0.70, green: 0.95, blue: 0.90), washTop: Color(red: 0.10, green: 0.36, blue: 0.38), washBottom: Color(red: 0.10, green: 0.20, blue: 0.24)),
        "amber": FocusPalette(name: "Amber", tint: Color(red: 1.0, green: 0.76, blue: 0.28), glow: Color(red: 1.0, green: 0.88, blue: 0.62), washTop: Color(red: 0.50, green: 0.32, blue: 0.14), washBottom: Color(red: 0.28, green: 0.20, blue: 0.14)),
        "indigo": FocusPalette(name: "Indigo", tint: Color(red: 0.42, green: 0.40, blue: 0.96), glow: Color(red: 0.76, green: 0.74, blue: 1.0), washTop: .clear, washBottom: .clear),
        "pink": FocusPalette(name: "Pink", tint: Color(red: 1.0, green: 0.25, blue: 0.42), glow: Color(red: 1.0, green: 0.74, blue: 0.82), washTop: .clear, washBottom: .clear),
        "orange": FocusPalette(name: "Orange", tint: Color(red: 1.0, green: 0.62, blue: 0.10), glow: Color(red: 1.0, green: 0.84, blue: 0.56), washTop: .clear, washBottom: .clear),
        "mint": FocusPalette(name: "Mint", tint: Color(red: 0.40, green: 0.90, blue: 0.80), glow: Color(red: 0.80, green: 1.0, blue: 0.95), washTop: .clear, washBottom: .clear),
        "purple": FocusPalette(name: "Purple", tint: Color(red: 0.78, green: 0.38, blue: 0.96), glow: Color(red: 0.90, green: 0.74, blue: 1.0), washTop: .clear, washBottom: .clear),
        "graphite": FocusPalette(name: "Graphite", tint: Color(red: 0.82, green: 0.86, blue: 0.92), glow: Color(red: 1.0, green: 1.0, blue: 1.0), washTop: Color(red: 0.26, green: 0.28, blue: 0.34), washBottom: Color(red: 0.14, green: 0.15, blue: 0.19)),
    ]
    static var current: FocusPalette { all[UserDefaults.standard.string(forKey: "focusPalette") ?? "red"] ?? all["red"]! }
}

/// The same words as docs/MANUAL.md, so help is one click away inside the app.
enum HelpContent {
    static let sections: [(title: String, items: [(q: String, a: String)])] = [
        ("Getting started", [
            ("What is Tarn?", "A calm Mac menu bar app. Focus runs timed work rounds with breaks. Breathe is a slow breathing animation. Sounds are optional. It is free, with no account and no tracking."),
            ("How do I start a round?", "Click the big circle, or press Start. Tap the length pill under it to choose 15, 25, 45, 60 or 90 minutes."),
            ("What does the length pill mean?", "The small pill under the circle is the length of one focus round. Tap it to change it. \"1 of 4\" is the round you are on. After the last round you get a longer break."),
            ("What happens on a break?", "The picture changes to a gentle breathing guide and the window turns soft purple. When the break ends, the next round starts on its own unless you turn that off in Settings."),
        ]),
        ("Breathe", [
            ("How do I use Breathe?", "Switch to Breathe. Breathe in as the picture opens and out as it closes. Click the picture to pause it."),
            ("What are Settle, Deep, Box and 4 7 8?", "Settle starts easy and slowly deepens over three minutes. Deep is in for 6, hold 2, out for 8. Box is in 4, hold 4, out 4, hold 4. 4 7 8 is in for 4, hold 7, out for 8."),
            ("What does Full screen do?", "It covers every screen with a calm background, including desktop icons. Click anywhere, press Esc, or use the Close button to go back. The sound buttons in the top right corner turn sound on or off and pick a mix."),
            ("What is Calm mode?", "One button for full screen, your last sound mix and Hide apps. Add two Shortcuts in Settings if you also want Do Not Disturb. Click anywhere or press Esc to come back."),
            ("What is a Session?", "Choose the Session length under the pattern buttons: 1, 3, 5, 10 or 20 minutes, or Open to keep going. When it ends, any sound you have on fades out, unless you keep it on in Settings. It works as a simple meditation timer too."),
            ("What does Hide apps do?", "It hides other apps' windows so you can breathe. It never quits anything. Press Bring back, or start a focus round, and they return."),
        ]),
        ("Sounds", [
            ("How do I turn sounds on?", "Open the Sounds tab and pick a preset or move a slider. Up to three sounds play at once. A fade out timer can stop them for you. Sounds are off until you choose them."),
        ]),
        ("Good to know", [
            ("I cannot find the icon.", "On some Macs the notch or a crowded menu bar hides it. Open Settings, then Open in a window, or turn on Show Tarn in the Dock."),
            ("Does Tarn collect anything?", "No. Everything stays on your Mac, including your stats."),
            ("Which Macs does it support?", "macOS 14 or later, on Apple silicon and Intel."),
            ("Can I control it from Terminal?", "Yes. Run tarnctl, for example tarnctl start 45 or tarnctl breathe full."),
        ]),
    ]
}

struct HelpTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.headline)
            ForEach(Array(HelpContent.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.q).font(.callout.weight(.medium))
                            Text(item.a).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
