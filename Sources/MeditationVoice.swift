import AVFoundation
import CoreAudio
import AudioToolbox
import SwiftUI

/// A guided meditation in Breathe: one recorded track per voice and length (`Voice/meditation-<voice>-<minutes>.m4a`),
/// played as one continuous piece, with the passage being spoken shown as a caption. The option only appears when tracks are present.
@MainActor
final class Meditation: ObservableObject {
    static let shared = Meditation()

    /// The session length while a guided session runs, nil otherwise.
    @Published private(set) var minutes: Int?
    /// The words on screen: the last thing the voice said, like a caption.
    @Published private(set) var caption = ""
    @Published private(set) var isPaused = false
    /// True when the Mac's output is muted or turned almost all the way down during a session.
    @Published private(set) var volumeLow = false
    /// Set for a few seconds after a session plays to the end.
    @Published private(set) var justFinished = false

    /// When the breathing begins. The welcome is spoken during the quiet lead-in before it.
    private(set) var start = Date()
    private var pausedFrom: Date?
    private var script: [VoiceLine] = []
    private var nextLine = 0
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    var isActive: Bool { minutes != nil }

    /// How loud the voice plays, remembered between sessions. Set with the Voice slider in a session.
    @Published var voiceLevel: Double = UserDefaults.standard.object(forKey: "meditationVoiceLevel") as? Double ?? 1 {
        didSet {
            UserDefaults.standard.set(voiceLevel, forKey: "meditationVoiceLevel")
            player?.volume = Float(voiceLevel)
        }
    }
    var total: Double { Double((minutes ?? 0) * 60) }

    /// Seconds since the first breath. Negative during the lead-in. Holds still while paused.
    func elapsed(at date: Date = Date()) -> Double { (pausedFrom ?? date).timeIntervalSince(start) }

    // MARK: Tracks

    /// Recorded voices, in the order they are offered.
    static let voices: [String] = ["soft", "warm", "male"].filter { v in lengths.contains { url(voice: v, minutes: $0) != nil } }
    static let lengths = [5, 10, 20]
    static var isAvailable: Bool { !voices.isEmpty }

    /// The chosen voice if it was recorded, else the first one that was.
    static func voice(preferring v: String) -> String { voices.contains(v) ? v : (voices.first ?? "soft") }

    static func label(_ v: String) -> String {
        switch v {
        case "soft": return "Soft"
        case "warm": return "Warm"
        default: return "Grounded"
        }
    }

    /// Session lengths in minutes with a recorded track for this voice.
    static func lengths(voice: String) -> [Int] { lengths.filter { url(voice: voice, minutes: $0) != nil } }

    private static func url(voice: String, minutes: Int) -> URL? {
        Bundle.main.url(forResource: "meditation-\(voice)-\(minutes)", withExtension: "m4a", subdirectory: "Voice")
    }

    // MARK: Session

    /// Starts the track. Its first seconds are the welcome, spoken during the lead-in. Sound plays softly
    /// underneath unless that is turned off in Settings.
    func begin(minutes m: Int) {
        if isActive { end(completed: false) }
        let d = UserDefaults.standard
        let voice = Self.voice(preferring: d.string(forKey: "meditationVoice") ?? "soft")
        guard let url = Self.url(voice: voice, minutes: m), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = Float(voiceLevel)
        p.prepareToPlay()
        p.play()
        player = p
        minutes = m
        start = Date().addingTimeInterval(VoiceScript.leadIn)
        pausedFrom = nil; isPaused = false; justFinished = false
        script = VoiceScript.timeline(total: Double(m * 60))
        nextLine = 0
        caption = ""
        if d.object(forKey: "meditationSounds") as? Bool ?? true {
            AppModel.shared.sound.beginMeditation(startedForBreathe: AppModel.shared.startedForBreathe)
        }
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        tick()
    }

    /// Pausing holds the voice, the breath and the clock. The sound is paused by the Breathe screen with them.
    func togglePause() {
        guard isActive else { return }
        if let at = pausedFrom {
            start = start.addingTimeInterval(Date().timeIntervalSince(at))
            pausedFrom = nil; isPaused = false
            player?.play()
        } else {
            pausedFrom = Date(); isPaused = true
            player?.pause()
        }
    }

    /// With `completed`, the closing words play out before the track is released.
    func end(completed: Bool) {
        guard isActive else { return }
        ticker?.invalidate(); ticker = nil
        minutes = nil
        isPaused = false; pausedFrom = nil
        volumeLow = false
        let d = UserDefaults.standard
        AppModel.shared.sound.endMeditation(lingerMinutes: d.integer(forKey: "meditationLinger"),
                                            keep: d.bool(forKey: "keepSoundAfterSession"))
        guard let p = player else { return }
        player = nil
        if completed {
            caption = VoiceScript.ending.text
            justFinished = true
            let left = max(0, p.duration - p.currentTime) + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + left) { p.stop() }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(left, 8)) { [weak self] in
                guard let self, !self.isActive else { return }
                self.justFinished = false
                self.caption = ""
            }
        } else {
            caption = ""
            p.setVolume(0, fadeDuration: 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { p.stop() }
        }
    }

    /// The track carries the voice; this keeps the caption in step with it and ends the session on time.
    private func tick() {
        let e = elapsed()
        while nextLine < script.count, script[nextLine].at <= e, script[nextLine].at < total {
            if script[nextLine].at >= 0 { caption = script[nextLine].passage.text }
            nextLine += 1
        }
        let low = SystemVolume.isLow()
        if low != volumeLow { volumeLow = low }
        if e >= total { end(completed: true) }
    }
}

/// Reads the default output device's mute and volume, so a guided session can say when the voice will not be heard.
enum SystemVolume {
    static func isLow() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr else { return false }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr, muted != 0 { return true }
        var volume: Float32 = 1
        size = UInt32(MemoryLayout<Float32>.size)
        addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                          mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        // Some outputs (many displays and interfaces) have no volume of their own; those are never called low.
        guard AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &volume) == noErr else { return false }
        return volume < 0.08
    }
}
