import SwiftUI

@main
struct StillwaterApp: App {
    @StateObject private var timer = PomodoroTimer()
    @StateObject private var sound = SoundEngine()

    var body: some Scene {
        MenuBarExtra {
            ContentView(timer: timer, sound: sound)
        } label: {
            if timer.isRunning || timer.remaining < timer.duration(for: timer.phase) {
                Text(timer.clockText).monospacedDigit()
            } else {
                Image(systemName: "leaf")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
