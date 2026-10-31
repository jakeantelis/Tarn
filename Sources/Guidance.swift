/// Gentle written guidance, in our own words. Advances every 26 seconds.
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
