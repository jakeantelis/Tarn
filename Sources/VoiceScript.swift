import Foundation

/// One spoken passage of the guided meditation. The recorded tracks in `Resources/Voice/` speak these in order.
/// Copied from TarnCore in Tarn for iOS, which builds the tracks from it. Keep the two in step until they share a package.
public struct Passage: Equatable, Sendable {
    public let id: String
    public let text: String
}

public struct VoiceLine: Equatable, Sendable {
    /// Seconds from the first breath. Negative times fall in the lead-in.
    public let at: Double
    public let passage: Passage
    public init(at: Double, passage: Passage) { self.at = at; self.passage = passage }
}

/// The guided meditation: a few calm passages with long quiet between them. Written in our own words.
public enum VoiceScript {
    /// Quiet seconds before the first breath, while the opening is spoken.
    public static let leadIn: Double = 14

    public static let opening = Passage(id: "opening", text: "Welcome. Find a position that feels easy, and let your eyes close if you like. There is nowhere else you need to be right now.")
    public static let middle: [Passage] = [
        Passage(id: "p01", text: "Take a slow breath in, and let it go. Let your shoulders soften, and your hands rest."),
        Passage(id: "p02", text: "Let your breath move on its own. You don't need to change it. Just notice it, coming in, and going out."),
        Passage(id: "p03", text: "Feel the weight of your body, resting, fully supported by what is beneath you."),
        Passage(id: "p04", text: "Soften your jaw. Let your tongue rest. Let the small muscles around your eyes relax."),
        Passage(id: "p05", text: "If thoughts come, that's alright. Let them pass like clouds, and come back to the breath."),
        Passage(id: "p06", text: "With each breath out, let a little more tension go."),
        Passage(id: "p07", text: "Notice the gentle rise and fall of your chest and belly."),
        Passage(id: "p08", text: "Notice any sounds around you. Let them come and go, without holding on."),
        Passage(id: "p09", text: "If your mind has wandered, that's perfectly fine. Gently begin again, with this breath."),
        Passage(id: "p10", text: "Bring your attention to your hands. Notice warmth, tingling, or simply stillness."),
        Passage(id: "p11", text: "There is nothing to do, and nowhere to get to. Just this moment, and this breath."),
        Passage(id: "p12", text: "Let yourself be here, just as you are."),
        Passage(id: "p13", text: "Rest here in the quiet for a while."),
    ]
    public static let closing = Passage(id: "closing", text: "In a moment, we will come back. Let your breath return to its own pace.")
    public static let ending = Passage(id: "ending", text: "Begin to notice the room around you. When you're ready, gently open your eyes.")

    public static var all: [Passage] { [opening] + middle + [closing, ending] }

    /// Seconds of quiet between passages. Longer sessions leave more room.
    static func gap(total: Double) -> Double {
        let minutes = total / 60
        return minutes <= 5 ? 32 : (minutes <= 10 ? 58 : 105)
    }

    /// When each passage is spoken in a session of `total` seconds.
    public static func timeline(total: Double) -> [VoiceLine] {
        var lines = [VoiceLine(at: -leadIn, passage: opening)]
        let gap = gap(total: total)
        let last = total - 60
        let slots = max(0, Int((last - 20) / gap) + 1)
        // Use the early passages in order, but always finish with the invitation to rest in quiet.
        var chosen = Array(middle.prefix(min(slots, middle.count)))
        if let rest = middle.last, slots > 0, chosen.last != rest { chosen[chosen.count - 1] = rest }
        for (i, p) in chosen.enumerated() { lines.append(VoiceLine(at: 20 + Double(i) * gap, passage: p)) }
        if total >= 90 { lines.append(VoiceLine(at: total - 35, passage: closing)) }
        lines.append(VoiceLine(at: total, passage: ending))
        return lines
    }
}
