import SwiftUI

@main
struct StillwaterApp: App {
    @StateObject private var timer = PomodoroTimer()
    @StateObject private var sound = SoundEngine()

    var body: some Scene {
        MenuBarExtra {
            ContentView(timer: timer, sound: sound)
        } label: {
            Group {
                if timer.mode.hasTimer && !timer.hideCountdown && (timer.isRunning || timer.remaining < timer.duration(for: timer.phase)) {
                    Text(timer.clockText).monospacedDigit()
                } else {
                    Image(systemName: "leaf")
                }
            }
            .onChange(of: timer.isRunning) { _, _ in syncSound() }
            .onChange(of: timer.phase) { _, _ in syncSound() }
            .onChange(of: timer.mode) { _, _ in syncSound() }
        }
        .menuBarExtraStyle(.window)
    }

    private func syncSound() {
        sound.sync(mode: timer.mode, phase: timer.phase, timerRunning: timer.isRunning)
    }
}
