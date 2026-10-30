import SwiftUI
import AppKit

@main
struct StillwaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var timer = AppModel.shared.timer
    @StateObject private var sound = AppModel.shared.sound

    var body: some Scene {
        MenuBarExtra {
            ContentView(timer: timer, sound: sound)
        } label: {
            HStack(spacing: 4) {
                if timer.mode.hasTimer && (timer.isRunning || timer.remaining < timer.duration(for: timer.phase)) {
                    Image(nsImage: ringIcon(progress: timer.progress))
                    if !timer.hideCountdown { Text(timer.clockText).monospacedDigit() }
                } else {
                    Image(nsImage: Self.idleIcon)
                }
            }
            .onChange(of: timer.isRunning) { _, _ in syncSound() }
            .onChange(of: timer.phase) { _, new in
                syncSound()
                guard timer.fullScreenBreaks, timer.isRunning, timer.mode.hasTimer else { return }
                if new.isBreak { BreatheOverlay.shared.show() } else { BreatheOverlay.shared.close() }
            }
            .onChange(of: timer.mode) { _, _ in syncSound() }
        }
        .menuBarExtraStyle(.window)
    }

    private func syncSound() {
        sound.sync(mode: timer.mode, phase: timer.phase, timerRunning: timer.isRunning)
    }

    /// Idle menu bar icon: a lens, meaning two rings and a dot. Drawn as a template so it follows the menu bar tint.
    static let idleIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setStroke()
            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 1.6, dy: 1.6)); outer.lineWidth = 1.5; outer.stroke()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 4.6, dy: 4.6)); inner.lineWidth = 1.2; inner.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()

    /// Small ring that fills as the round progresses; drawn as a template so it follows the menu bar tint.
    private func ringIcon(progress: Double) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            let r = rect.insetBy(dx: 2, dy: 2)
            let track = NSBezierPath(ovalIn: r)
            track.lineWidth = 1.6
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            let c = NSPoint(x: rect.midX, y: rect.midY)
            arc.appendArc(withCenter: c, radius: r.width / 2, startAngle: 90,
                          endAngle: 90 - 360 * CGFloat(max(0.02, progress)), clockwise: true)
            arc.lineWidth = 1.8
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }
}
