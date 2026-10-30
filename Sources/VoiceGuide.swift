import AVFoundation

/// Optional spoken breathing cues using Apple's on device speech synthesis.
/// No audio files and no network, so nothing to license and no size cost.
@MainActor
final class VoiceGuide {
    static let shared = VoiceGuide()
    private let synth = AVSpeechSynthesizer()
    private var last = ""

    var enabled: Bool { UserDefaults.standard.bool(forKey: "voiceGuide") }

    func cue(_ label: String) {
        guard enabled, label != last else { return }
        last = label
        let text: String
        switch label {
        case "Breathe in": text = "Breathe in"
        case "Breathe out": text = "And out"
        default: text = "Hold"
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.softVoice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.7
        u.pitchMultiplier = 0.9
        u.volume = 0.55
        synth.stopSpeaking(at: .word)
        synth.speak(u)
    }

    /// Speaks a longer guidance line, softly, if spoken cues are on.
    func say(_ text: String) {
        guard enabled else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.softVoice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.65
        u.pitchMultiplier = 0.9
        u.volume = 0.5
        synth.speak(u)
    }

    func reset() {
        last = ""
        synth.stopSpeaking(at: .immediate)
    }

    /// Prefer the best installed English voice (Premium, then Enhanced).
    private static let softVoice: AVSpeechSynthesisVoice? = {
        let en = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return en.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()
}

/// Gentle spoken or written guidance, in our own words. Advances every 26 seconds.
enum Guidance {
    static let lines = [
        "Settle in. Let your shoulders drop.",
        "Unclench your jaw. Soften your face.",
        "Let your breath find its own pace.",
        "Nothing to fix right now. Just notice.",
        "If thoughts come, let them pass like clouds.",
        "Feel your feet, your seat, your weight.",
        "With each breath out, let a little more go.",
        "You are doing this exactly right.",
    ]
    static func index(at t: Double) -> Int { Int(max(0, t) / 26) }
    static func line(at t: Double) -> String { lines[index(at: t) % lines.count] }
}
