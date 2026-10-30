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
