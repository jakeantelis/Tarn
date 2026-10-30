import SwiftUI
import AppKit

enum Mode: String, CaseIterable, Identifiable {
    case pomodoro = "Pomodoro", breathe = "Breathe"
    var id: String { rawValue }
    var hasTimer: Bool { self == .pomodoro }
    var blurb: String {
        switch self {
        case .pomodoro: return "Focus in rounds with timed breaks."
        case .breathe: return "Slow down any time. No timer needed."
        }
    }
}

enum Preset: String, CaseIterable, Identifiable {
    case classic = "Classic", deep = "Deep", custom = "Custom"
    var id: String { rawValue }
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

/// When ambient sound plays during Pomodoro sessions.
enum SoundScope: String, CaseIterable, Identifiable {
    case always = "Always", focus = "Focus only", breaks = "Breaks only"
    var id: String { rawValue }
}

@MainActor
final class PomodoroTimer: ObservableObject {
    @Published var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .pomodoro
    @Published var phase: Phase = .work
    @Published var remaining: TimeInterval = 25 * 60
    @Published var isRunning = false
    @Published var completedRounds = 0

    @AppStorage("preset") var presetRaw = Preset.classic.rawValue
    @AppStorage("customWorkMinutes") var customWork = 25
    @AppStorage("customShortMinutes") var customShort = 5
    @AppStorage("customLongMinutes") var customLong = 15
    @AppStorage("autoStartNext") var autoStartNext = true
    @AppStorage("breakStyle") var breakStyleRaw = BreakStyle.breathe.rawValue
    @AppStorage("chime") var chime = true

    private var endDate: Date?
    private var ticker: Timer?

    init() { remaining = duration(for: .work) }

    var preset: Preset {
        get { Preset(rawValue: presetRaw) ?? .classic }
        set {
            objectWillChange.send()
            presetRaw = newValue.rawValue
            if !isRunning { remaining = duration(for: phase) }
        }
    }

    var breakStyle: BreakStyle { BreakStyle(rawValue: breakStyleRaw) ?? .breathe }

    /// Rounds before a long break.
    var roundsPerSet: Int { preset == .deep ? 3 : 4 }

    func setMode(_ new: Mode) {
        guard new != mode else { return }
        stopTicker()
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: "mode")
        phase = .work
        completedRounds = 0
        remaining = duration(for: .work)
    }

    func duration(for phase: Phase) -> TimeInterval {
        let m: (work: Int, short: Int, long: Int)
        switch preset {
        case .classic: m = (25, 5, 15)
        case .deep: m = (50, 10, 20)
        case .custom: m = (customWork, customShort, customLong)
        }
        switch phase {
        case .work: return TimeInterval(m.work * 60)
        case .shortBreak: return TimeInterval(m.short * 60)
        case .longBreak: return TimeInterval(m.long * 60)
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
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
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
        advance(autoStart: false)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            stopTicker()
            if chime { NSSound(named: "Glass")?.play() }
            advance(autoStart: autoStartNext)
        }
    }

    private func advance(autoStart: Bool) {
        if phase == .work {
            completedRounds += 1
            phase = completedRounds % roundsPerSet == 0 ? .longBreak : .shortBreak
        } else {
            phase = .work
        }
        remaining = duration(for: phase)
        if autoStart { start() }
    }
}
