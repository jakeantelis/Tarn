import AppKit

/// When Tarn is opened straight from the disk image or the Downloads folder, offers to move itself into
/// Applications. One quiet question, asked once. Nothing happens unless the person says yes.
@MainActor
enum MoveToApplications {
    private static let askedKey = "moveToApplicationsAsked"
    private static let destination = URL(fileURLWithPath: "/Applications/Tarn.app")

    /// Only a copy that is running from a disk image or the Downloads folder is worth moving.
    nonisolated static func shouldOffer(path: String) -> Bool {
        if path.hasPrefix("/Applications/") || path.contains("/Applications/") && path.hasPrefix(NSHomeDirectory()) { return false }
        return path.hasPrefix("/Volumes/") || path.contains("/Downloads/") || path.contains("/AppTranslocation/")
    }

    /// Returns true when it took over (the app is about to quit and reopen from Applications).
    static func offerIfNeeded() -> Bool {
        let path = Bundle.main.bundlePath
        guard shouldOffer(path: path), !UserDefaults.standard.bool(forKey: askedKey) else { return false }
        UserDefaults.standard.set(true, forKey: askedKey)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Tarn to your Applications folder?"
        alert.informativeText = "Tarn will live there from now on, so it is easy to find and keeps working after you eject the disk image."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return move(from: URL(fileURLWithPath: path))
    }

    private static func move(from source: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            let replace = NSAlert()
            replace.messageText = "Replace the Tarn already in Applications?"
            replace.informativeText = "The older copy will be moved to the Trash."
            replace.addButton(withTitle: "Replace")
            replace.addButton(withTitle: "Cancel")
            guard replace.runModal() == .alertFirstButtonReturn else { return false }
            // Close any running copy first, so the old one can be swapped out cleanly.
            NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0 != NSRunningApplication.current }.forEach { $0.terminate() }
            do { try fm.trashItem(at: destination, resultingItemURL: nil) }
            catch { return failed() }
        }
        do { try fm.copyItem(at: source, to: destination) } catch { return failed() }

        // Reopen from Applications, then eject the disk image if that is where we came from.
        var script = "sleep 0.8; /usr/bin/open -n '\(destination.path)'"
        if source.path.hasPrefix("/Volumes/") {
            let volume = source.pathComponents.prefix(3).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
            script += "; sleep 2; /usr/sbin/diskutil eject '\(volume)' >/dev/null 2>&1"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        NSApp.terminate(nil)
        return true
    }

    private static func failed() -> Bool {
        let a = NSAlert()
        a.messageText = "Tarn could not be moved"
        a.informativeText = "That is fine. You can drag Tarn into the Applications folder yourself, or just keep using it from here."
        a.runModal()
        return false
    }
}
