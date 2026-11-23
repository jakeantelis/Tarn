/// Tarn ships two ways: the direct download (Developer ID, Sparkle updates) and the Mac App Store.
/// The App Store build is made with `./build.sh appstore`, which defines APPSTORE. It runs in the App
/// Sandbox, updates through the Store, and leaves out what the sandbox does not allow: Sparkle, the
/// move-to-Applications offer and the tarnctl installer.
enum Edition {
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}
