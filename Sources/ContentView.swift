import SwiftUI
import ServiceManagement

extension Color {
    static let onTint = Color(red: 0.13, green: 0.11, blue: 0.09)
    static var focusTint: Color { FocusPalette.current.tint }
    static let amber = Color(red: 0.98, green: 0.80, blue: 0.48)
    static let water = Color(red: 0.32, green: 0.64, blue: 0.78)
}

/// Reports how tall the content wants to be, so a window can be exactly that tall and leave no empty space.
struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ContentView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    @State private var tab: Int          // 0 timer, 1 breathe, 2 sounds
    init(timer: PomodoroTimer, sound: SoundEngine, initialTab: Int = 0) {
        self.timer = timer; self.sound = sound; _tab = State(initialValue: initialTab)
    }
    @State private var fullScreenOfferDismissed = false
    @AppStorage("offerFullScreen") private var offerFullScreen = true
    @AppStorage("allowScreenTakeover") private var allowTakeover = true
    @AppStorage("floatingCircle") private var floatingOn = true
    @State private var popoverActive = true
    @State private var chromeVisible = true
    @State private var lastActivity = Date()
    @State private var lastMouse = NSEvent.mouseLocation
    @AppStorage("welcomed") private var welcomed = false
    @AppStorage("eveningWarmth") private var eveningWarmth = false   // re-renders the colors when changed
    @AppStorage("showTips") private var showTips = false
    @AppStorage("focusPalette") private var paletteKey = "red"

    private var onBreak: Bool { timer.mode.hasTimer && timer.phase.isBreak }
    private var breakTint: some View {
        let g: [Color]
        if timer.mode == .breathe { g = [Color.breatheTint.opacity(0.14), Color.breatheTint.opacity(0.04)] }
        else if onBreak { g = [Color.purple.opacity(0.16), Color.purple.opacity(0.04)] }
        else { g = [Color.white.opacity(0.05), Color.white.opacity(0.0)] }
        return LinearGradient(colors: g, startPoint: .top, endPoint: .bottom)
    }
    private func wake() {
        lastActivity = Date()
        if !chromeVisible { chromeVisible = true }
    }

    private var effectiveTab: Int { timer.mode.hasTimer ? (tab == 2 || tab == 3 ? tab : 0) : (tab == 2 ? 2 : 1) }

    var body: some View {
        VStack(spacing: 12) {
                PillPicker(items: Mode.allCases, selection: Binding(get: { timer.mode }, set: { m in timer.setMode(m); AppModel.shared.userChose(m) })) { $0.rawValue }
                    .help("Focus: Pomodoro rounds with calm breaks. Breathe: slow down any time, no timer.")
                    .fadesWithChrome(chromeVisible)

                // Focus has three tabs. Breathe has none: it is just the picture, with sounds one tap away in Options.
                if timer.mode.hasTimer {
                    PillPicker(items: [0, 3, 2],
                               selection: Binding(get: { effectiveTab }, set: { tab = $0 })) { $0 == 2 ? "Sounds" : ($0 == 3 ? "Stats" : "Timer") }
                        .padding(.horizontal, 30)
                        .fadesWithChrome(chromeVisible)
                } else if effectiveTab == 2 {
                    HStack {
                        Text("Sounds").font(.headline)
                        Spacer()
                        Button("Back to breathing") { tab = 1 }.buttonStyle(CapsuleButtonStyle(small: true))
                    }
                }

                Group {
                switch effectiveTab {
                case 0: TimerTab(timer: timer)
                case 3: StatsTab(stats: StatsStore.shared)
                case 1:
                    VStack(spacing: 12) {
                        if sound.isPlaying && !AppModel.shared.startedForBreathe && offerFullScreen && allowTakeover && !fullScreenOfferDismissed {
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
                            .task {
                                try? await Task.sleep(nanoseconds: 10_000_000_000)
                                withAnimation { fullScreenOfferDismissed = true }
                            }
                        }
                        BreathingView(onMix: { tab = 2 })
                        let q = Lines.calmQuote(Int(Date().timeIntervalSinceReferenceDate / 90))
                        QuoteLine(text: q.text, author: q.author)
                            .padding(.top, 16).padding(.bottom, 6)   // clear of the card above and the footer below
                            .fadesWithChrome(chromeVisible)
                    }
                default: MixerTab(sound: sound)
                }
                }
                .id("\(timer.mode.rawValue)-\(effectiveTab)")
                .transition(.identity)   // switching screens snaps cleanly, with no overlapping crossfade

            if showTips && welcomed { TipLine().fadesWithChrome(chromeVisible) }
            HStack {
                do {
                    Button {
                        sound.toggle()
                    } label: {
                        Image(systemName: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(sound.isPlaying ? "Sound is on. Click to turn it off." : "Sound is off. Click to turn it on.")
                    .accessibilityLabel(sound.isPlaying ? "Turn sound off" : "Turn sound on")
                }
                Menu {
                    Section("Focus") {
                        Button("Start 25 minutes") { timer.setMode(.pomodoro); AppModel.shared.userChose(.pomodoro); timer.startWork(minutes: 25) }
                        Button("Start 45 minutes") { timer.setMode(.pomodoro); AppModel.shared.userChose(.pomodoro); timer.startWork(minutes: 45) }
                        if timer.isRunning { Button("Pause") { timer.pause() } }
                        else if timer.mode.hasTimer && timer.remaining < timer.duration(for: timer.phase) { Button("Resume") { timer.start() } }
                    }
                    Section("Breathe") {
                        Button("Open Breathe") { timer.setMode(.breathe); AppModel.shared.userChose(.breathe) }
                        if allowTakeover {
                            Button("Calm mode") { AppModel.shared.calmMode() }
                            Button("Full screen") { BreatheOverlay.shared.show() }
                        }
                    }
                    Section("Tarn") {
                        Button("Open in a window") { WindowOpener.shared.show() }
                        Toggle("Floating circle", isOn: Binding(get: { floatingOn }, set: { floatingOn = $0; FloatingCircle.shared.refresh() }))
                        Button("Settings…") { SettingsWindowOpener.shared.show(timer.mode == .breathe ? .breathe : .focus) }
                        Button("Help and FAQ") { SettingsWindowOpener.shared.show(.help) }
                        Button("About Tarn") { AboutPanel.show() }
                        Button("Quit Tarn") { NSApplication.shared.terminate(nil) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.leading, 6)
                .help("Quick actions")
                .accessibilityLabel("Quick actions")
                Spacer()
                Button("Help") { SettingsWindowOpener.shared.show(.help) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10)
                    .help("Questions and answers, with search")
                Button("Settings") { SettingsWindowOpener.shared.show(timer.mode == .breathe ? .breathe : .focus) }
                    .buttonStyle(.borderless)
                    .help("Open the settings window")
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
            }
            .font(.callout)
            .fadesWithChrome(chromeVisible)
        }
        .padding(16)
        .frame(width: 300)
        .frame(minHeight: welcomed ? 0 : 500)   // the welcome card needs room to show all of its text
        .fixedSize(horizontal: false, vertical: true)   // report the real content height, never a squeezed one
        .background(GeometryReader { g in Color.clear.preference(key: ContentHeightKey.self, value: g.size.height) })
        .background(PopoverVisibilityReader(active: $popoverActive))
        .environment(\.popoverActive, popoverActive)
        .environment(\.chromeVisible, chromeVisible)
        .onContinuousHover { phase in if case .active = phase { wake() } }
        .onChange(of: timer.mode) { _, _ in wake() }
        .onChange(of: popoverActive) { _, active in if active { wake() } }   // opening the popover always shows the controls
        .onChange(of: tab) { _, _ in wake() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Only while you are breathing, with nothing else open, and only after a few quiet seconds.
            let breathing = timer.mode == .breathe && effectiveTab == 1 && popoverActive
            // The pointer moving over any Tarn window counts as activity, even if no hover event arrives.
            let loc = NSEvent.mouseLocation
            if loc != lastMouse {
                lastMouse = loc
                if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(loc) }) { wake() }
            }
            if breathing, chromeVisible, Date().timeIntervalSince(lastActivity) > 6 { chromeVisible = false }
            if !breathing, !chromeVisible { chromeVisible = true }
        }
        .onChange(of: sound.isPlaying) { _, playing in if !playing { fullScreenOfferDismissed = false } }
        .background(breakTint)
        .tint(timer.mode == .breathe ? Color.breatheTint : FocusPalette.all[paletteKey]?.tint ?? Color.focusTint)
        .animation(.easeInOut(duration: 1.2), value: onBreak)
        .animation(.easeInOut(duration: 0.6), value: timer.mode)
        .overlay { if !welcomed { Welcome { mode in welcomed = true; timer.setMode(mode); AppModel.shared.userChose(mode) } } }
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
    /// Called with the mode the person wants to start in.
    let done: (Mode) -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                Text("Welcome to Tarn").font(.title3.weight(.medium))
                Text("A tarn is a small, still mountain lake.")
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(.secondary)
                Text("Quiet enough to hold the sky. Work in focused rounds, then breathe like still water.")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            // Two worlds, two clear choices. Focus is first and a little larger, because it is the main idea.
            VStack(spacing: 10) {
                choice(title: "Focus", line: "Timed rounds with calm breaks", symbol: "timer",
                       color: Color.focusTint, tall: true) { done(.pomodoro) }
                choice(title: "Breathe", line: "Slow down any time. No timer.", symbol: "wind",
                       color: Color.breatheTint, tall: false) { done(.breathe) }
            }

            VStack(spacing: 4) {
                Text("Focus is silent. Breathe plays a soft sound you can switch off. Everything is yours to set up in [**Settings**](tarn://settings).")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "tarn" { SettingsWindowOpener.shared.show(.focus); return .handled }
                        return .systemAction
                    })
            }

            QuoteLine(text: Lines.focus[0].text, author: Lines.focus[0].author)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func choice(title: String, line: String, symbol: String, color: Color, tall: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: tall ? 24 : 20, weight: .light))
                    .foregroundStyle(color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: tall ? 18 : 16, weight: .semibold))
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(color.opacity(0.8))
            }
            .padding(.horizontal, 16).padding(.vertical, tall ? 18 : 14)
            .background(RoundedRectangle(cornerRadius: 20).fill(color.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.45), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(line)")
    }
}

struct QuoteLine: View {
    let text: String
    var author: String? = nil
    var body: some View {
        VStack(spacing: 3) {
            Text("\u{201C}\(text)\u{201D}")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.primary.opacity(0.82))
                .lineSpacing(2)
            if let author {
                Text(author.uppercased())
                    .font(.system(size: 10, weight: .medium)).tracking(1.2)
                    .foregroundStyle(Color.primary.opacity(0.55))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 6)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct TimerTab: View {
    @ObservedObject var timer: PomodoroTimer

    @AppStorage("tapToStart") private var tapToStart = true
    @State private var hoveringLens = false

    /// The line under the countdown. It always says what a click will do when that matters.
    private var lensHint: String {
        guard tapToStart else { return timer.isRunning ? timer.nextLine : "Ready" }
        if timer.isRunning { return hoveringLens ? "Click to pause" : timer.nextLine }
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
                VStack(spacing: 6) {
                    Text(timer.phase.rawValue.uppercased())
                        .font(.caption.weight(.semibold)).tracking(1.5)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Color.purple.opacity(0.22)))
                        .foregroundStyle(Color.purple)
                    BreathingView(compact: true, still: !timer.isRunning)
                    Text(timer.clockText)
                        .font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                    Text(timer.isRunning ? "Next: Focus \(timer.effectiveMinutes) min" : "Press Start when you are ready")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(height: 250)
            } else {
                ZStack {
                    LensView(progress: timer.progress, running: timer.isRunning)
                    VStack(spacing: 6) {
                        Text(timer.phase.isBreak ? timer.phase.rawValue.uppercased() : "FOCUS")
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
                        RoundDots(timer: timer).padding(.top, 2)
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
                    ForEach(timer.lengthChoices, id: \.self) { m in
                        Button { timer.setFocusMinutes(m) } label: {
                            let name = m == 1 ? "1 minute" : "\(m) minutes"
                            if timer.effectiveMinutes == m { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                    Divider()
                    Button("Other…") { askCustomLength(timer) }
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
                Button(timer.isRunning ? "Pause" : (timer.phase.isBreak ? "Start break" : "Start")) { timer.toggle() }
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

enum SettingsSection: String, CaseIterable, Identifiable {
    case focus = "Focus", breathe = "Breathe", general = "General", help = "Help and FAQ"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .focus: return "timer"
        case .breathe: return "wind"
        case .general: return "gearshape"
        case .help: return "questionmark.circle"
        }
    }
}

struct SettingsTab: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    let section: SettingsSection
    @AppStorage("offerFullScreen") private var offerFullScreen = true
    @AppStorage("allowScreenTakeover") private var allowTakeover = true
    @AppStorage("breathStyle") private var breathStyle = BreathStyle.bloom.rawValue
    @AppStorage("focusPalette") private var paletteKey = "red"
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("allowLinks") private var allowLinks = true
    @AppStorage("showTips") private var showTips = false
    @StateObject private var updates = UpdateChecker()
    @State private var cliInstalled = CommandLineTool.isInstalled
    @State private var cliFailed = false
    @AppStorage("calmStartShortcut") private var calmStart = ""
    @AppStorage("calmEndShortcut") private var calmEnd = ""
    @AppStorage("eveningWarmth") private var eveningWarmth = false
    @AppStorage("keepSoundAfterSession") private var keepSound = false
    @AppStorage("breatheSound") private var breatheSound = true
    @AppStorage("gentleFades") private var gentleFades = true
    @AppStorage("guideMe") private var guideMe = false
    @AppStorage("meditationVoice") private var meditationVoice = "soft"
    @AppStorage("offerMeditation") private var offerMeditation = true
    @AppStorage("meditationSounds") private var soundsUnderMeditation = true
    @AppStorage("meditationLinger") private var lingerMinutes = 0
    @AppStorage("breathPattern") private var breathPattern = "settle"
    @AppStorage("hideOthersWhenBreathing") private var hideOthers = true
    @AppStorage("soundEnabled") private var soundEnabled = false
    @AppStorage("soundScope") private var scopeRaw = SoundScope.always.rawValue
    @AppStorage("floatingCircle") private var floating = true
    @AppStorage("floatingSize") private var floatingSize = 0
    @AppStorage("floatingOpacity") private var floatingOpacity = 0.9
    @AppStorage("floatingClickThrough") private var floatingClickThrough = false

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { timer.objectWillChange.send(); set($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.rawValue).font(.title2.weight(.semibold))
            if section != .help {
                Text(section == .general
                     ? "Set Tarn up your way. Every option is optional, and nothing hides your apps or fills your screen unless you ask it to."
                     : "Everything here is optional. Change what you like and leave the rest.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            switch section {
            case .focus: pomodoro
            case .breathe: breathe
            case .general: general
            case .help: HelpTab(showTitle: false)
            }
        }
        .font(.callout)
        .groupBoxStyle(FullWidthGroupBox())
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Tarn \(UpdateChecker.currentVersion)")
                        Spacer()
                        switch updates.state {
                        case .available(_, let url):
                            Button("Download") { NSWorkspace.shared.open(url) }.buttonStyle(CapsuleButtonStyle(prominent: true, small: true))
                        default:
                            Button(updates.state == .checking ? "Checking…" : "Check for updates") { updates.check() }
                                .buttonStyle(CapsuleButtonStyle(small: true)).disabled(updates.state == .checking)
                        }
                    }
                    switch updates.state {
                    case .upToDate: Label("You are up to date.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .available(let v, _): Label("Version \(v) is available.", systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                    case .failed:
                        Text("Could not check right now. Try again later, or look on the [releases page](\(UpdateChecker.releasesPage.absoluteString)).")
                            .font(.caption).foregroundStyle(.secondary)
                    default: EmptyView()
                    }
                    Text("Tarn only goes online when you press Check for updates. It asks GitHub for the newest version and sends nothing about you. Nothing installs by itself: you download the new version and drag it over the old one.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            GroupBox("Command line") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if cliInstalled {
                            Label("tarnctl is installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Remove") { CommandLineTool.remove(); cliInstalled = CommandLineTool.isInstalled }
                                .buttonStyle(CapsuleButtonStyle(small: true))
                        } else {
                            Text("Control Tarn from Terminal, scripts and shortcuts.")
                            Spacer()
                            Button("Install tarnctl") { cliFailed = !CommandLineTool.install(); cliInstalled = CommandLineTool.isInstalled }
                                .buttonStyle(CapsuleButtonStyle(prominent: true, small: true))
                        }
                    }
                    if cliFailed { Text("Could not install. Try again from the Tarn app in your Applications folder.").font(.caption).foregroundStyle(.red) }
                    if cliInstalled && !CommandLineTool.onPath {
                        Text("One more step so Terminal finds it. Paste this line into Terminal once, then open a new Terminal window:")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(CommandLineTool.pathLine).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            Button("Copy") { CommandLineTool.copy(CommandLineTool.pathLine) }.buttonStyle(CapsuleButtonStyle(small: true))
                        }
                        .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                    }
                    Text("Try: tarnctl start 45 · tarnctl pause · tarnctl breathe · tarnctl calm · tarnctl status. Run tarnctl help for the full list. Turn off \u{201C}Allow tarnctl and tarn:// links\u{201D} below to block it.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }.padding(.vertical, 4)
            }
            GroupBox("Startup and windows") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open Tarn at login", isOn: Binding(get: { loginOn }, set: { setLogin($0) }))
                    Toggle("Allow tarnctl and tarn:// links", isOn: $allowLinks)
                    Toggle("Show Tarn in the Dock", isOn: $showInDock)
                        .onChange(of: showInDock) { _, _ in WindowOpener.applyDockPolicy() }
                    Toggle("Show a short tip at the bottom of the window", isOn: $showTips)
                    HStack(spacing: 6) {
                        Button("Open in a window") { WindowOpener.shared.show() }
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
                    Text("A tarn is a small, still mountain lake, quiet enough to hold the sky. Tarn is a calm place to focus, and to breathe.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Free and open source, made by Antelis Labs. No account and no tracking. The recorded sounds are public domain (CC0) from BigSoundBank.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Button("About Tarn") { AboutPanel.show() }.buttonStyle(CapsuleButtonStyle(small: true))
                        Button("Show the welcome again") { UserDefaults.standard.set(false, forKey: "welcomed"); WindowOpener.shared.show() }
                            .buttonStyle(CapsuleButtonStyle(small: true))
                    }
                }.padding(.vertical, 4)
            }
        }
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
            GroupBox("Rounds") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Focus length", selection: Binding(get: { timer.effectiveMinutes },
                                                              set: { $0 == 0 ? askCustomLength(timer) : timer.setFocusMinutes($0) })) {
                        ForEach(timer.lengthChoices, id: \.self) { Text("\($0) min").tag($0) }
                        Divider()
                        Text("Other…").tag(0)
                    }
                    Text("Breaks scale with the focus length.").font(.caption).foregroundStyle(.secondary)
                    Picker("After a round", selection: bind({ timer.afterRound }, { timer.afterRoundRaw = $0.rawValue })) {
                        ForEach(AfterRound.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Breaks", selection: bind({ timer.breakStyle }, { timer.breakStyleRaw = $0.rawValue })) {
                        ForEach(BreakStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if timer.afterRound == .takeBreak {
                        Toggle("Start next round automatically", isOn: bind({ timer.autoStartNext }, { timer.autoStartNext = $0 }))
                    }
                    Toggle("Click the circle to start and pause", isOn: Binding(get: { UserDefaults.standard.object(forKey: "tapToStart") as? Bool ?? true }, set: { timer.objectWillChange.send(); UserDefaults.standard.set($0, forKey: "tapToStart") }))
                    Toggle("Gentle reminder when a round ends", isOn: bind({ timer.roundReminder }, { timer.roundReminder = $0; if $0 { Notifier.requestPermission() } }))
                }.padding(.vertical, 4)
            }
            GroupBox("Floating circle") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show a small floating circle", isOn: $floating)
                    if floating {
                        Picker("Size", selection: $floatingSize) {
                            ForEach(0..<FloatingCircle.sizeNames.count, id: \.self) { Text(FloatingCircle.sizeNames[$0]).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("Opacity")
                            Slider(value: $floatingOpacity, in: 0.3...1)
                        }
                        Toggle("Let clicks pass through it", isOn: $floatingClickThrough)
                    }
                    Text(floating
                         ? "It shows the timer in Focus and the breathing picture in Breathe. Drag it anywhere. It steps aside in full screen. If clicks pass through, switch this off here to move it again."
                         : "Off. A small circle can stay above your other windows so you can see the time without opening Tarn.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
                .onChange(of: floating) { _, _ in FloatingCircle.shared.refresh() }
                .onChange(of: floatingSize) { _, _ in FloatingCircle.shared.refresh() }
                .onChange(of: floatingOpacity) { _, _ in FloatingCircle.shared.refresh() }
                .onChange(of: floatingClickThrough) { _, _ in FloatingCircle.shared.refresh() }
            }
            GroupBox("Sound while focusing") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Play sounds while I focus", isOn: $soundEnabled)
                    if !soundEnabled { Text("Off. Focus is silent unless you turn this on.").font(.caption).foregroundStyle(.secondary) }
                    if soundEnabled {
                        Picker("Play during", selection: $scopeRaw) {
                            ForEach(SoundScope.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        Text(scopeRaw == SoundScope.always.rawValue ? "Soft during work, fuller on breaks. Choose the mix on the Sounds tab." : "Choose the mix on the Sounds tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
            GroupBox("Daily schedule") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Run focus rounds automatically each day", isOn: bind({ timer.scheduleEnabled }, { timer.scheduleEnabled = $0 }))
                    if timer.scheduleEnabled {
                        HStack {
                            DatePicker("From", selection: minutesBinding(\.scheduleStart), displayedComponents: .hourAndMinute)
                            DatePicker("until", selection: minutesBinding(\.scheduleEnd), displayedComponents: .hourAndMinute)
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
                            Spacer(minLength: 8)
                            Button("Workday") {
                                timer.objectWillChange.send()
                                timer.scheduleStart = 9 * 60; timer.scheduleEnd = 17 * 60; timer.scheduleDays = 0b0111110
                            }
                            .buttonStyle(CapsuleButtonStyle(small: true))
                            .help("9:00 to 17:00, Monday to Friday")
                        }
                    }
                    Text(timer.scheduleEnabled
                         ? "At the start time Tarn begins a focus round, then alternates focus and breaks by itself until the end time. It needs to be open: turn on Open at login in General. If Tarn opens more than 30 minutes late, that day's start is skipped."
                         : "Off. Turn it on to have Tarn run focus and break rounds on its own, such as 9 to 5 on weekdays.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
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
              }
            }
            .padding(.vertical, 2)
        }
    }

    private var breathe: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Sound") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Play a soft sound when I breathe", isOn: $breatheSound)
                    Toggle("Keep the sound playing when a session or Calm ends", isOn: $keepSound)
                    Toggle("Gentle fades", isOn: $gentleFades)
                    Text("The sound starts when you open Breathe, begin a session or use Calm mode, and fades out when a session ends. Turn it off here, with the speaker button, or in the Options menu. Pick or mix sounds from Options on the Breathe screen. Gentle fades ease sound out over a few seconds when you pause it, and over 30 seconds after a meditation or the sleep timer. Off, sound stops almost at once. Each sound also drifts a little louder and softer over a few minutes, and birds move gently left and right, so a long day never sounds the same twice.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            if Meditation.isAvailable {
                GroupBox("Guided meditation") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Offer guided meditation", isOn: $offerMeditation)
                        Group {
                        if Meditation.voices.count > 1 {
                            Picker("Voice", selection: Binding(get: { Meditation.voice(preferring: meditationVoice) }, set: { meditationVoice = $0 })) {
                                ForEach(Meditation.voices, id: \.self) { Text(Meditation.label($0)).tag($0) }
                            }
                        }
                        Toggle("Play sounds under the voice", isOn: $soundsUnderMeditation)
                        Picker("Sounds afterwards", selection: $lingerMinutes) {
                            Text("Fade over 30 seconds").tag(0)
                            Text("Stay 3 minutes").tag(3)
                            Text("Stay 10 minutes").tag(10)
                        }
                        .disabled(!soundsUnderMeditation)
                        }
                        .disabled(!offerMeditation)
                        Text("The voice only plays when you choose a guided meditation. Breathe and its sessions stay quiet otherwise. Start one with the Guided meditation button on the Breathe screen, or from Options: 5, 10 or 20 minutes. A quiet voice guides you with long stretches of silence, and your sound mix plays softly underneath, or Nature calm if you have none. Sound that started for the meditation drifts away afterwards. Sound you had on already goes back to its normal level. Switch it off to hide the button and the menu items. Best with headphones and your eyes closed.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 4)
                }
            }
            GroupBox("Look and rhythm") {
                VStack(alignment: .leading, spacing: 8) {
                    PillPicker(items: BreathStyle.allCases.map(\.rawValue), selection: $breathStyle) { $0 }
                    Picker("Rhythm", selection: $breathPattern) {
                        ForEach(BreathPattern.all) { Text($0.name).tag($0.id) }
                    }
                    Text((BreathPattern.all.first { $0.id == breathPattern } ?? .settle).blurb)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Warmer colors in the evening", isOn: $eveningWarmth)
                    Toggle("Show gentle written prompts while I breathe", isOn: $guideMe)
                }.padding(.vertical, 4)
            }
            GroupBox("Screen and apps") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Allow full screen and hiding apps", isOn: $allowTakeover)
                    Group {
                        Toggle("Offer full screen when I turn sound on", isOn: $offerFullScreen)
                        Toggle("Hide other apps in full screen", isOn: $hideOthers)
                        Toggle("Fill the screen on Focus breaks", isOn: Binding(get: { timer.fullScreenBreaks }, set: { timer.objectWillChange.send(); timer.fullScreenBreaks = $0 }))
                    }
                    .disabled(!allowTakeover)
                    Text("Off means Tarn never covers your screen or hides another app. Apps are only ever hidden, never quit, and they come back when you leave.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            DisclosureGroup("Advanced") {
              VStack(alignment: .leading, spacing: 12) {
            GroupBox("Calm mode shortcuts") {
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
                    Text("Optional. To silence notifications, make two Shortcuts with the Set Focus action: one that turns Do Not Disturb on and one that turns it off. Leave these blank to skip.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
              }
            }
            .padding(.vertical, 2)
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
            ("What is Tarn?", "A calm Mac menu bar app. Focus runs timed work rounds with breaks. Breathe is a slow breathing animation. It is free, with no account and no tracking."),
            ("Where do I find things?", "Click the flower in the menu bar. The switch at the top moves between Focus and Breathe. Help, Settings and Quit are along the bottom. Settings has four sections: Focus, Breathe, General, and this Help."),
            ("How do I update Tarn?", "Open Settings, General, Updates and press Check for updates. If a newer version exists, press Download, then drag the new Tarn over the old one in Applications. Tarn never checks by itself."),
            ("How do I install or move Tarn?", "Open the disk image and drag Tarn onto Applications. If you open Tarn straight from the disk image or Downloads, it offers once to move itself into Applications for you."),
            ("I cannot find the menu bar icon.", "On some Macs the notch or a crowded menu bar hides it. Open Settings, General, and turn on Show Tarn in the Dock, then click the Dock icon to open a window. You can also run tarnctl window in Terminal."),
        ]),
        ("Focus", [
            ("How do I start a round?", "Click the big circle, or press Start. Tap the length pill under it to choose 15, 25, 45, 60 or 90 minutes, or Other for any length from 1 to 180."),
            ("Can a round end without a break?", "Yes. In Settings, Focus, set After a round to Stop. Tarn counts the round and waits on a fresh one, with no break."),
            ("What does the length pill mean?", "The small pill under the circle is the length of one focus round. The dots inside the circle show your rounds: a filled dot is finished and a ring is the one you are on. After the last dot you get a longer break."),
            ("What happens on a break?", "The picture changes to a gentle breathing guide and the window turns soft purple. The break waits until you start it. When it ends, the next round starts on its own unless you turn that off in Settings, Focus."),
            ("Can Tarn run my day for me?", "Yes. In Settings, Focus, open Daily schedule. Turn it on, choose a start and end time and the days, or press Workday for 9 to 5 on weekdays. Tarn then alternates focus and breaks until the end time. It needs to be open, so turn on Open at login in General."),
            ("Can I silence notifications while I focus?", "Yes. In Settings, Focus, Advanced, name two Shortcuts from the Shortcuts app, one that turns a Focus mode on and one that turns it off. Tarn runs them when a round starts and ends."),
            ("What is the floating circle?", "A small circle that stays above your other windows. In Focus it shows the time, and in Breathe it shows the breathing picture. Click it to start or pause, hover for a sound button, and drag it anywhere. Change its size, or turn it off, in Settings, Focus, or from the three dots menu. It steps aside in full screen."),
            ("Does the timer pause by itself?", "Yes, when your Mac sleeps or locks. You can turn that off in Settings, Focus, Advanced."),
        ]),
        ("Breathe", [
            ("How do I use Breathe?", "Switch to Breathe. Breathe in as the picture opens and out as it closes. Click the picture to pause it. The sound and any session clock pause too."),
            ("What are Settle, Deep, Box and 4 7 8?", "They are breathing rhythms. Settle starts easy and slowly deepens over three minutes. Deep is in for 6, hold 2, out for 8. Box is in 4, hold 4, out 4, hold 4. 4 7 8 is in for 4, hold 7, out for 8. Choose one in Options under Rhythm, or in Settings, Breathe."),
            ("What is a session?", "In Options choose a session length of 1, 3, 5, 10 or 20 minutes, or No timer to keep going. When it ends, the sound fades out, which is your quiet cue that it is time to get back. You can keep the sound playing in Settings, Breathe. It works as a simple meditation timer too."),
            ("Does Breathe play sound?", "Yes, a soft sound by default, starting when you open Breathe, begin a session or use Calm mode. Switch it off with the speaker button, in Options, or in Settings, Breathe, Sound."),
            ("How do I go full screen?", "Press the small expand button next to Options, or choose Full screen in Options under More. Click anywhere, press Esc, or use Close to go back. The buttons in the top right corner turn sound on or off and pick a mix."),
            ("What is Calm mode?", "One button for full screen, your last sound mix and Hide other apps. When you leave, the sound fades out unless you keep it playing in Settings. Add two Shortcuts in Settings, Breathe if you also want Do Not Disturb."),
            ("What does Hide other apps do?", "It hides other apps' windows so you can breathe. It never quits anything. Choose Bring back hidden apps in Options, or start a focus round, and they return. Quitting Tarn brings them back too. You can switch full screen and hiding off completely in Settings, Breathe, Screen and apps."),
            ("Where did the controls go?", "While you breathe and the mouse is still, the controls fade and the picture grows to fill the window. Move the mouse and the controls come back."),
        ]),
        ("Sounds", [
            ("How do I turn sounds on in Focus?", "Open the Sounds tab, pick a preset or move a slider. Up to three sounds play at once. A fade out timer can stop them for you. Focus is silent unless you turn sounds on, and Settings, Focus, Sound while focusing lets Tarn play them for you during rounds."),
            ("How do I change the sound in Breathe?", "Open Options, then Sound. Pick a preset, or choose Mix sounds for sliders."),
        ]),
        ("Privacy and extras", [
            ("Does Tarn collect anything?", "No. Everything stays on your Mac, including your stats. There is no account and no tracking. Tarn only goes online when you press Check for updates."),
            ("Which Macs does it support?", "macOS 14 or later, on Apple silicon and Intel."),
            ("Can I control it from Terminal?", "Yes. Open Settings, General, Command line and press Install tarnctl. Then in Terminal run tarnctl start 45, tarnctl pause, tarnctl breathe, tarnctl calm or tarnctl status. tarnctl help lists everything. You can switch it off with Allow tarnctl in General."),
            ("What are Tips?", "Short hints at the bottom of the window. They are off by default. Turn them on in Settings, General."),
        ]),
    ]
}

/// The FAQ: searchable, with each answer tucked under its question so the page stays easy to scan.
struct HelpTab: View {
    var showTitle = true
    @State private var query = ""
    @State private var open: Set<String> = []

    private func matches(_ item: (q: String, a: String)) -> Bool {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return true }
        let hay = (item.q + " " + item.a).lowercased()
        return words.allSatisfy { hay.contains($0) }
    }

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 14) {
            if showTitle { Text("Help and FAQ").font(.headline) }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search help", text: $query).textFieldStyle(.plain)
                if searching {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.14)))

            let visible = HelpContent.sections.map { sec in (sec.title, sec.items.filter(matches)) }.filter { !$0.1.isEmpty }
            if visible.isEmpty {
                Text("Nothing matches \u{201C}\(query)\u{201D}. Try a simpler word, like sound, break or screen.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(visible.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.0.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                    ForEach(Array(section.1.enumerated()), id: \.offset) { _, item in
                        let expanded = searching || open.contains(item.q)
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                if open.contains(item.q) { open.remove(item.q) } else { open.insert(item.q) }
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.q).font(.callout.weight(.medium)).multilineTextAlignment(.leading)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                        .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if expanded {
                                Text(item.a).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 2)
                        Divider().opacity(0.5)
                    }
                }
            }
            Text("Full manual: docs/MANUAL.md in the Tarn repository.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One short, optional hint. Chosen by the hour, so it holds still while you work.
enum Tips {
    static let all = [
        "Click the picture in Breathe to pause it. The sound pauses too.",
        "Press the small expand button in Breathe to go full screen. Esc brings you back.",
        "A 25 minute round with a 5 minute break is the classic Pomodoro. Try 45 for deeper work.",
        "Breaks wait until you start them, so finish your thought first.",
        "Daily schedule, in Settings, Focus, runs your whole day on its own.",
        "Calm mode gives you full screen, sound and hidden apps in one button.",
        "Rhythm in the Breathe Options menu changes the pace of your breath.",
        "Name a Shortcut in Settings to switch on Do Not Disturb while you focus.",
        "Breathe sessions end with the sound fading out. That is your cue to get back.",
        "Tarn never speaks and never collects anything. Tips can be switched off in Settings.",
    ]
    static var current: String {
        let n = Int(Date().timeIntervalSinceReferenceDate / 3600)
        return all[n % all.count]
    }
}

struct TipLine: View {
    var body: some View {
        Label(Tips.current, systemImage: "lightbulb")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// Your place in the set, as quiet dots: filled for finished rounds, a ring for the one you are on.
struct RoundDots: View {
    @ObservedObject var timer: PomodoroTimer
    private var done: Int {
        let n = timer.roundsPerSet
        if timer.phase == .longBreak { return n }
        return timer.completedRounds % n
    }

    var body: some View {
        let total = timer.roundsPerSet
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                let isDone = i < done
                let isCurrent = !timer.phase.isBreak && i == done
                Circle()
                    .fill(isDone ? Color.focusTint : Color.clear)
                    .overlay(Circle().stroke(Color.focusTint.opacity(isCurrent ? 0.95 : 0.35), lineWidth: isCurrent ? 1.6 : 1))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round \(min(done + (timer.phase.isBreak ? 0 : 1), total)) of \(total)")
        .help("Rounds in this set. After the last one you get a longer break.")
    }
}


/// Settings groups that always run the full width, so every section lines up the same way.
struct FullWidthGroupBox: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label.font(.callout.weight(.medium))
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10)))
        }
    }
}

/// Opens the Other… prompt and keeps the length it returns, so it stays in the list.
@MainActor func askCustomLength(_ timer: PomodoroTimer) {
    guard let m = CustomLengthPrompt.ask(current: timer.effectiveMinutes) else { return }
    timer.customMinutes = PomodoroTimer.focusChoices.contains(m) ? timer.customMinutes : m
    timer.setFocusMinutes(m)
}
