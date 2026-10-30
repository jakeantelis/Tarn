import SwiftUI
import AppKit

/// A normal window with the same controls as the menu bar popover. It is a fallback for when the menu bar
/// icon is hard to find (a crowded bar or the notch can hide it), and it is what the Dock icon opens.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let model = AppModel.shared
            // The hosting view must not drive window sizing. Animated content that changes its own height
            // otherwise triggers endless layout passes and an AppKit exception, so the window has a fixed size.
            let host = NSHostingView(rootView: ContentView(timer: model.timer, sound: model.sound)
                .frame(width: 300, height: 620, alignment: .top))
            host.sizingOptions = []
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Tarn"
            w.isReleasedWhenClosed = false
            w.contentView = host
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func applyDockPolicy() {
        let show = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }
}
