import Foundation

/// "Check for updates" asks GitHub once, only when the button is pressed. Nothing about the person is sent,
/// there is no background checking, and nothing is installed automatically.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, url: URL)
        case failed
    }

    static let releasesPage = URL(string: "https://github.com/jakeantelis/Tarn/releases")!
    private static let endpoint = URL(string: "https://api.github.com/repos/jakeantelis/Tarn/releases/latest")!

    @Published private(set) var state: State = .idle

    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// True when `latest` is a higher version than `current`. Accepts a leading "v" and ignores anything after a dash.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("v") { t.removeFirst() }
            t = String(t.split(separator: "-").first ?? "")
            return t.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tarn", forHTTPHeaderField: "User-Agent")   // GitHub requires one; it carries no version or identity
        let session = URLSession(configuration: .ephemeral)          // no cookies, no cache, nothing kept
        Task {
            do {
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else { state = .failed; return }
                if Self.isNewer(tag, than: Self.currentVersion) {
                    let page = (json["html_url"] as? String).flatMap(URL.init(string:))
                    // Only ever send people to this project's own releases.
                    let safe = page.flatMap { $0.absoluteString.hasPrefix("https://github.com/jakeantelis/Tarn/") ? $0 : nil } ?? Self.releasesPage
                    state = .available(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: safe)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed
            }
        }
    }
}
