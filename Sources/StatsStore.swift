import Foundation

/// Local only focus stats. Nothing leaves the Mac.
struct DayStats: Codable { var rounds = 0; var minutes = 0 }

@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()
    @Published private(set) var days: [String: DayStats]

    private static let key = "stats.v1"
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let v = try? JSONDecoder().decode([String: DayStats].self, from: d) { days = v } else { days = [:] }
    }

    static func id(_ date: Date) -> String { fmt.string(from: date) }

    func record(minutes: Int) {
        var d = days[Self.id(Date())] ?? DayStats()
        d.rounds += 1; d.minutes += minutes
        days[Self.id(Date())] = d
        if let data = try? JSONEncoder().encode(days) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    var today: DayStats { days[Self.id(Date())] ?? DayStats() }

    /// Last seven days, oldest first.
    var week: [(label: String, stats: DayStats, isToday: Bool)] {
        let cal = Calendar.current
        return (0..<7).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: Date())!
            let letter = String(cal.shortWeekdaySymbols[cal.component(.weekday, from: d) - 1].prefix(1))
            return (letter, days[Self.id(d)] ?? DayStats(), back == 0)
        }
    }

    /// Consecutive days with at least one round, counting today only if it has one.
    var streak: Int {
        let cal = Calendar.current
        var n = 0
        var date = Date()
        if today.rounds == 0 { date = cal.date(byAdding: .day, value: -1, to: date)! }
        while (days[Self.id(date)]?.rounds ?? 0) > 0 {
            n += 1
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return n
    }
}
