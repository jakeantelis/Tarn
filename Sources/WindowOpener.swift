import SwiftUI
import AppKit

/// A normal window with the same controls as the menu bar popover. It is a fallback for when the menu bar
/// icon is hard to find (a crowded bar or the notch can hide it), and it is what the Dock icon opens.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    private var window: NSWindow?
    private var pendingFit: DispatchWorkItem?

    /// Sizes the window to the content, once things have settled. The height only changes when you switch screens,
    /// never every frame, which is what keeps this safe from AppKit layout loops.
    func fit(toContentHeight h: CGFloat) {
        guard h > 0 else { return }
        pendingFit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let w = self.window else { return }
            let target = max(440, min(h, 780))
            let current = w.contentRect(forFrameRect: w.frame).height
            guard abs(target - current) > 3 else { return }
            var f = w.frame
            let newHeight = w.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 300, height: target)).height
            f.origin.y = f.maxY - newHeight          // keep the top edge where it is
            f.size.height = newHeight
            w.setFrame(f, display: true, animate: false)
        }
        pendingFit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func show() {
        if window == nil {
            let model = AppModel.shared
            // The hosting view must not drive window sizing. Animated content that changes its own height
            // otherwise triggers endless layout passes and an AppKit exception, so the window has a fixed size.
            let host = NSHostingView(rootView: ContentView(timer: model.timer, sound: model.sound)
                .frame(width: 300, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .onPreferenceChange(ContentHeightKey.self) { h in WindowOpener.shared.fit(toContentHeight: h) })
            host.sizingOptions = []
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 560),
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
