import SwiftUI
import AppKit

enum Mode: String, CaseIterable, Identifiable {
    case pomodoro = "Focus", breathe = "Breathe"
    var id: String { rawValue }
    var hasTimer: Bool { self == .pomodoro }
    var blurb: String {
        switch self {
        case .pomodoro: return "Pomodoro rounds with calm, timed breaks."
        case .breathe: return "Slow down any time. No timer needed."
        }
    }
}

enum Phase: String {
    case work = "Focus"
    case shortBreak = "Short break"
    case longBreak = "Long break"

    var isBreak: Bool { self != .work }
}

/// What happens when a break starts.
enum BreakStyle: String, CaseIterable, Identifiable {
    case breathe = "Guided breathing", plain = "Plain countdown"
    var id: String { rawValue }
}

/// When ambient sound plays during Pomodoro sessions. Both is soft during work and fuller on breaks.
enum SoundScope: String, CaseIterable, Identifiable {
    case focus = "Focus", breaks = "Breaks", always = "Both"
    var id: String { rawValue }
}

@MainActor
final class PomodoroTimer: ObservableObject {
    @Published var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .pomodoro
    @Published var phase: Phase = .work
    @Published var remaining: TimeInterval = 25 * 60
    @Published var isRunning = false
    @Published var completedRounds = 0

    /// Focus length in minutes. Breaks scale with it (see breakMinutes).
    @AppStorage("focusMinutes") var focusMinutes = 25
    static let focusChoices = [15, 25, 45, 60, 90]
    /// 60 in normal use. Tests set TARN_SECONDS_PER_MINUTE to a small number so a whole round can run in seconds.
    static let secondsPerMinute: Double = Double(ProcessInfo.processInfo.environment["TARN_SECONDS_PER_MINUTE"] ?? "") ?? 60

    @AppStorage("autoStartNext") var autoStartNext = true
    @AppStorage("breakStyle") var breakStyleRaw = BreakStyle.breathe.rawValue
    @AppStorage("fullScreenBreaks") var fullScreenBreaks = false
    @AppStorage("roundReminder") var roundReminder = false
    @AppStorage("intention") var intention = ""
    @AppStorage("eyeRest") var eyeRest = false
    @Published var eyeRestUntil = Date.distantPast
    private var lastEyeBlock = 0
    private var lastWritten = -1
    @AppStorage("focusStartShortcut") var focusStartShortcut = ""
    @AppStorage("focusEndShortcut") var focusEndShortcut = ""
    @AppStorage("pauseOnLock") var pauseOnLock = true
    @AppStorage("hideCountdown") var hideCountdown = false
    private var focusActive = false
    /// A length asked for by a link or tarnctl. It applies to this session only and never overwrites the saved choice.
    private(set) var overrideMinutes: Int?
    var effectiveMinutes: Int { overrideMinutes ?? focusMinutes }

    // Daily schedule: auto start the first round at a set time and stop at the end time.
    @AppStorage("scheduleEnabled") var scheduleEnabled = false
    @AppStorage("scheduleStart") var scheduleStart = 9 * 60          // minutes after midnight
    @AppStorage("scheduleEnd") var scheduleEnd = 17 * 60
    @AppStorage("scheduleDays") var scheduleDays = 0b0111110          // Sun=bit0 ... Sat=bit6, default Mon to Fri
    @AppStorage("scheduleLastStart") private var lastStartDay = ""
    @AppStorage("scheduleLastEnd") private var lastEndDay = ""
    private var scheduleTimer: Timer?

    /// Called after the timer starts, stops, changes phase or changes mode, so sound and screen effects follow the timer itself.
    var onStateChange: (() -> Void)?

    private var endDate: Date?
    private var ticker: Timer?

    init() {
        remaining = duration(for: .work)
        let pause: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pauseOnLock else { return }
                self.pause()
            }
        }
        let st = Timer(timeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkSchedule() } }
        RunLoop.main.add(st, forMode: .common)
        scheduleTimer = st
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: pause)
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: pause)
    }

    private func checkSchedule() {
        guard scheduleEnabled else { return }
        let cal = Calendar.current, now = Date()
        let weekday = cal.component(.weekday, from: now) - 1            // Sunday = 0
        guard scheduleDays & (1 << weekday) != 0 else { return }
        let minute = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let day = ISO8601DateFormatter().string(from: cal.startOfDay(for: now))
        if minute >= scheduleStart, minute < min(scheduleEnd, scheduleStart + 30), lastStartDay != day {
            lastStartDay = day
            if !isRunning { phase = .work; completedRounds = 0; remaining = duration(for: .work); start() }
        }
        if minute >= scheduleEnd, lastEndDay != day, lastStartDay == day {
            lastEndDay = day
            reset()
        }
    }

    /// Runs a Shortcut the user named (for example to switch on Do Not Disturb). Nothing runs unless they set one.
    private func runShortcut(_ name: String) { runShortcutNamed(name) }

    private func setFocusActive(_ on: Bool) {
        guard on != focusActive else { return }
        focusActive = on
        runShortcut(on ? focusStartShortcut : focusEndShortcut)
    }

    func setFocusMinutes(_ m: Int) {
        objectWillChange.send()
        overrideMinutes = nil
        focusMinutes = m
        if !isRunning && phase == .work { remaining = duration(for: .work) }
    }

    private var breakMinutes: (short: Int, long: Int) {
        switch effectiveMinutes {
        case ..<31: return (5, 15)
        case ..<46: return (10, 20)
        case ..<61: return (10, 25)
        default: return (15, 30)
        }
    }

    /// Describes the phase that follows the current one, for the "Next" line.
    var nextLabel: String {
        func mins(_ p: Phase) -> Int { Int(duration(for: p) / Self.secondsPerMinute) }
        if phase.isBreak { return "Focus \(mins(.work)) min" }
        let next: Phase = (completedRounds + 1) % roundsPerSet == 0 ? .longBreak : .shortBreak
        return "\(next == .longBreak ? "Long break" : "Break") \(mins(next)) min"
    }

    var breakStyle: BreakStyle { BreakStyle(rawValue: breakStyleRaw) ?? .breathe }

    /// Rounds before a long break.
    var roundsPerSet: Int { effectiveMinutes > 30 ? 3 : 4 }

    /// Switching between Focus and Breathe only changes what you are looking at. A running round keeps going,
    /// so you can breathe for a minute and come back to the same countdown.
    func setMode(_ new: Mode) {
        guard new != mode else { return }
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: "mode")
        onStateChange?()
    }

    /// Starts a fresh focus round, from any phase.
    func startWork(minutes: Int? = nil) {
        stopTicker()
        overrideMinutes = minutes
        objectWillChange.send()
        lastEyeBlock = 0
        phase = .work
        remaining = duration(for: .work)
        start()
    }

    /// Starts a break now, from any phase.
    func startBreak() {
        stopTicker()
        phase = (completedRounds + 1) % roundsPerSet == 0 ? .longBreak : .shortBreak
        remaining = duration(for: phase)
        start()
    }

    func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .work: return TimeInterval(effectiveMinutes) * Self.secondsPerMinute
        case .shortBreak: return TimeInterval(breakMinutes.short) * Self.secondsPerMinute
        case .longBreak: return TimeInterval(breakMinutes.long) * Self.secondsPerMinute
        }
    }

    var progress: Double {
        let total = duration(for: phase)
        return total > 0 ? 1 - remaining / total : 0
    }

    var clockText: String {
        let s = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        setFocusActive(phase == .work)
        if phase == .work { ScreenClearer.shared.restore() }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        writeStatus()
        onStateChange?()
    }

    func pause() {
        guard isRunning else { return }
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
        stopTicker()
    }

    func reset() {
        stopTicker()
        remaining = duration(for: phase)
    }

    func skip() {
        stopTicker()
        advance(autoStart: false, completed: false)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
        setFocusActive(false)
        writeStatus()
        onStateChange?()
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if eyeRest, phase == .work {
            let block = Int((duration(for: .work) - remaining) / (20 * Self.secondsPerMinute))
            if block > lastEyeBlock, remaining > 90 {
                eyeRestUntil = Date().addingTimeInterval(20)   // a quiet banner only, no sound
            }
            lastEyeBlock = block
        }
        if Int(remaining) != lastWritten { writeStatus() }
        if remaining <= 0 {
            if phase == .work { StatsStore.shared.record(minutes: Int(duration(for: .work) / Self.secondsPerMinute)) }
            stopTicker()
            if roundReminder, phase == .work { Notifier.post("Round complete", "Take a slow breath. Your break is starting.") }
            advance(autoStart: autoStartNext)
        }
    }

    /// Writes a small status file so tarnctl status can read it.
    func writeStatus() {
        lastWritten = Int(remaining)
        let dict: [String: Any] = [
            "mode": mode.rawValue.lowercased(),
            "phase": phase.rawValue,
            "running": isRunning,
            "remainingSeconds": Int(remaining),
            "completedToday": StatsStore.shared.today.rounds,
        ]
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tarn")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: dict) { try? data.write(to: dir.appendingPathComponent("status.json")) }
    }

    private func advance(autoStart: Bool, completed: Bool = true) {
        lastEyeBlock = 0
        if phase == .work {
            if completed { completedRounds += 1 }
            phase = completedRounds % roundsPerSet == 0 && completed ? .longBreak : .shortBreak
        } else {
            phase = .work
        }
        remaining = duration(for: phase)
        if autoStart { start() } else { writeStatus(); onStateChange?() }
    }
}
