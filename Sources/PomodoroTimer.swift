import SwiftUI
import AppKit

enum Phase: String {
    case work = "Focus"
    case shortBreak = "Short break"
    case longBreak = "Long break"

    var isBreak: Bool { self != .work }
}

@MainActor
final class PomodoroTimer: ObservableObject {
    @Published var phase: Phase = .work
    @Published var remaining: TimeInterval = 25 * 60
    @Published var isRunning = false
    @Published var completedRounds = 0

    @AppStorage("workMinutes") var workMinutes = 25
    @AppStorage("shortBreakMinutes") var shortBreakMinutes = 5
    @AppStorage("longBreakMinutes") var longBreakMinutes = 15
    @AppStorage("autoStartNext") var autoStartNext = true

    private var endDate: Date?
    private var ticker: Timer?

    init() { remaining = duration(for: .work) }

    func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .work: return TimeInterval(workMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
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
            NSSound(named: "Glass")?.play()
            advance(autoStart: autoStartNext)
        }
    }

    private func advance(autoStart: Bool) {
        if phase == .work {
            completedRounds += 1
            phase = completedRounds % 4 == 0 ? .longBreak : .shortBreak
        } else {
            phase = .work
        }
        remaining = duration(for: phase)
        if autoStart { start() }
    }
}
