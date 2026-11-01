import Foundation
import Sparkle

/// Updates come through Sparkle (MIT). On its second launch Tarn asks once whether to check automatically;
/// until then, and if the answer is no, it only checks when you press Check for updates. A check reads
/// appcast.xml from this project on GitHub and sends no profile of the Mac. Every update is signed with
/// Tarn's own key, and Sparkle refuses one that does not match.
@MainActor
final class UpdateChecker: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = UpdateChecker()

    static let releasesPage = URL(string: "https://github.com/jakeantelis/Tarn/releases")!
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// False while a check is already running.
    @Published private(set) var canCheck = false

    private var controller: SPUStandardUpdaterController!
    private var observation: NSKeyValueObservation?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in
            let can = u.canCheckForUpdates
            Task { @MainActor in self?.canCheck = can }
        }
    }

    func check() { controller.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyInstalls: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Tarn lives in the menu bar, so a scheduled update is shown without taking focus from what you are doing.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }
}
