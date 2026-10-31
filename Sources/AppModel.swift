import Foundation
import AppKit
import Combine

/// One shared instance of the timer and sound engine, so the menu bar UI and URL commands drive the same state.
@MainActor
final class AppModel {
    static let shared = AppModel()
    let timer = PomodoroTimer()
    let sound = SoundEngine()
    private var fullScreenForBreak = false

    private var soundWatch: AnyCancellable?

    private init() {
        timer.onStateChange = { [weak self] in self?.timerChanged() }
        // Once the sound stops for any reason, it is no longer "Breathe's" sound, so Focus never stops a mix you started later.
        soundWatch = sound.$isPlaying.sink { [weak self] playing in if !playing { self?.startedForBreathe = false } }
    }

    /// Brings every hidden app back and drops the overlay, so quitting Tarn never leaves your screen changed.
    func restoreScreen() {
        BreatheOverlay.shared.close("quit")
        ScreenClearer.shared.restore()
    }

    /// Keeps sound and full screen breathing in step with the timer, whatever started the change (window, shortcut or tarnctl).
    private func timerChanged() {
        sound.sync(mode: timer.mode, phase: timer.phase, timerRunning: timer.isRunning)
        FloatingCircle.shared.refresh()
        if timer.fullScreenBreaks, timer.isRunning, timer.phase.isBreak, !BreatheOverlay.shared.isShowing {
            fullScreenForBreak = true
            BreatheOverlay.shared.show()
        } else if fullScreenForBreak, !timer.phase.isBreak {
            fullScreenForBreak = false
            BreatheOverlay.shared.close()
        }
    }

    /// Breathing sessions start a soft sound unless it is switched off in Settings. A mix already playing is left alone.
    func startBreatheSound() {
        guard UserDefaults.standard.object(forKey: "breatheSound") as? Bool ?? true, !sound.isPlaying else { return }
        let name = UserDefaults.standard.string(forKey: "lastPreset") ?? "Ocean calm"
        if let p = SoundPreset.all.first(where: { $0.name == name }) ?? SoundPreset.all.first { sound.applyPreset(p); startedForBreathe = true }
    }

    private(set) var startedForBreathe = false

    /// You chose a mode yourself. Breathe starts the soft sound; going back to Focus fades out what Breathe started.
    func userChose(_ mode: Mode) {
        if mode == .breathe { startBreatheSound() }
        else if startedForBreathe {
            startedForBreathe = false
            if !UserDefaults.standard.bool(forKey: "keepSoundAfterSession") { sound.stop() }
        }
    }

    /// One button: full screen, hide apps (if allowed), your last sound mix, and the optional Shortcut for Do Not Disturb.
    func calmMode() {
        guard BreatheOverlay.allowed else { return }
        timer.setMode(.breathe)
        startBreatheSound()
        runShortcutNamed(UserDefaults.standard.string(forKey: "calmStartShortcut") ?? "")
        BreatheOverlay.shared.calmActive = true
        BreatheOverlay.shared.show()
    }

    /// Handles tarn:// links, which is also what the tarnctl command line tool sends.
    func handle(_ url: URL) {
        guard url.scheme == "tarn" else { return }
        // Links and tarnctl can be switched off entirely in Settings. They are on by default.
        guard UserDefaults.standard.object(forKey: "allowLinks") as? Bool ?? true else { return }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch url.host ?? "" {
        case "start", "work":
            timer.setMode(.pomodoro)
            let m = value("minutes").flatMap(Int.init).flatMap { (1...240).contains($0) ? $0 : nil }
            timer.startWork(minutes: m)
        case "pause": timer.pause()
        case "resume": timer.start()
        case "toggle": timer.setMode(.pomodoro); timer.toggle()
        case "stop", "reset": timer.reset()
        case "skip": timer.skip()
        case "break":
            timer.setMode(.pomodoro); timer.startBreak()
        case "breathe":
            timer.setMode(.breathe)
            if value("fullscreen") == "1" { BreatheOverlay.shared.show() }
        case "sound":
            let preset: SoundPreset? = value("preset").flatMap { n in
                SoundPreset.all.first { $0.name.lowercased().hasPrefix(n.lowercased()) }
            }
            if let preset { sound.applyPreset(preset) }
            switch value("state") ?? (preset == nil ? "toggle" : "none") {
            case "on": if preset == nil { sound.play() }
            case "off": sound.stop()
            case "toggle": sound.toggle()
            default: break
            }
        case "window": WindowOpener.shared.show()
        case "settings":
            let section = SettingsSection.allCases.first { $0.rawValue.lowercased().hasPrefix((value("section") ?? "").lowercased()) && value("section") != nil }
            SettingsWindowOpener.shared.show(section ?? .focus)
        case "help": SettingsWindowOpener.shared.show(.help)
        case "about": AboutPanel.show()
        case "calm": calmMode()
        case "clear": ScreenClearer.shared.clear()
        case "restore": ScreenClearer.shared.restore()
        default: break
        }
        timer.writeStatus()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opened from the disk image or Downloads? Offer to move into Applications first. If it moves, this copy quits.
        if MoveToApplications.offerIfNeeded() { return }
        WindowOpener.applyDockPolicy()
        Task { @MainActor in AppModel.shared.timer.writeStatus() }   // so tarnctl status works straight after launch
        Task { @MainActor in FloatingCircle.shared.refresh() }
        // On the very first launch, open a window so Tarn is easy to find even if the menu bar icon is hidden.
        if UserDefaults.standard.object(forKey: "welcomed") == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { WindowOpener.shared.show() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.restoreScreen() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowOpener.shared.show()
        return true
    }

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
        guard BreatheOverlay.allowed, hidden.isEmpty else { return }
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
