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
            let host = NSHostingView(rootView: ContentView(timer: model.timer, sound: model.sound))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Tarn"
            w.isReleasedWhenClosed = false
            w.contentView = host
            w.center()
            window = w
        }
        window?.setContentSize(window?.contentView?.fittingSize ?? NSSize(width: 300, height: 560))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func applyDockPolicy() {
        let show = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }
}
