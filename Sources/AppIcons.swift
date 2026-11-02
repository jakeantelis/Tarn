import AppKit

/// The Dock icon can be changed in Settings, General. Classic is the icon inside the app. The others are tiles
/// in Resources/Icons. Only the Dock and the app switcher change, the icon in Finder stays Classic.
enum AppIcons {
    struct Choice: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    static let classicKey = "classic"
    static let all: [Choice] = [
        Choice(key: classicKey, name: "Classic"),
        Choice(key: "slate", name: "Slate"),
        Choice(key: "sage", name: "Sage"),
        Choice(key: "dusk", name: "Dusk"),
        Choice(key: "sand", name: "Sand"),
        Choice(key: "night", name: "Night"),
    ]

    /// A saved choice that is not in the list, for example from a newer version, falls back to Classic.
    static func resolvedKey(_ key: String?) -> String {
        guard let key, all.contains(where: { $0.key == key }) else { return classicKey }
        return key
    }

    static func image(for key: String) -> NSImage? {
        if key == classicKey {
            return Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
        }
        return Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "Icons").flatMap { NSImage(contentsOf: $0) }
    }

    @MainActor static func apply() {
        let key = resolvedKey(UserDefaults.standard.string(forKey: "appIcon"))
        // Setting nil puts the icon from the app itself back.
        NSApp.applicationIconImage = key == classicKey ? nil : image(for: key)
    }
}
