import Foundation
import AppKit

/// One shared instance of the timer and sound engine, so the menu bar UI and URL commands drive the same state.
@MainActor
final class AppModel {
    static let shared = AppModel()
    let timer = PomodoroTimer()
    let sound = SoundEngine()

    /// Handles stillwater:// links, which is also what the stillwaterctl command line tool sends.
    func handle(_ url: URL) {
        guard url.scheme == "stillwater" else { return }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch url.host ?? "" {
        case "start", "work":
            timer.setMode(.pomodoro)
            if let m = value("minutes").flatMap(Int.init), (1...240).contains(m) { timer.setFocusMinutes(m) }
            timer.start()
        case "pause": timer.pause()
        case "resume": timer.start()
        case "toggle": timer.setMode(.pomodoro); timer.toggle()
        case "stop", "reset": timer.reset()
        case "skip": timer.skip()
        case "break":
            timer.setMode(.pomodoro); timer.skip(); timer.start()
        case "breathe":
            timer.setMode(.breathe)
            if value("fullscreen") == "1" { BreatheOverlay.shared.show() }
        case "sound":
            switch value("state") ?? "toggle" {
            case "on": sound.play()
            case "off": sound.stop()
            default: sound.toggle()
            }
            if let name = value("preset")?.lowercased(),
               let p = SoundPreset.all.first(where: { $0.name.lowercased().hasPrefix(name) }) { sound.applyPreset(p) }
        case "clear": ScreenClearer.shared.clear()
        case "restore": ScreenClearer.shared.restore()
        default: break
        }
        timer.writeStatus()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in urls.forEach { AppModel.shared.handle($0) } }
    }
}

/// Hides other apps' windows (never quits them) and brings back exactly the ones it hid.
@MainActor
final class ScreenClearer: ObservableObject {
    static let shared = ScreenClearer()
    @Published private(set) var hidden: [NSRunningApplication] = []
    var isCleared: Bool { !hidden.isEmpty }

    func clear() {
        guard hidden.isEmpty else { return }
        hidden = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0 != NSRunningApplication.current
        }
        hidden.forEach { $0.hide() }
    }

    func restore() {
        hidden.forEach { $0.unhide() }
        hidden = []
    }
}
