import SwiftUI
import AppKit

@main
struct StillwaterApp: App {
    @StateObject private var timer = PomodoroTimer()
    @StateObject private var sound = SoundEngine()

    var body: some Scene {
        MenuBarExtra {
            ContentView(timer: timer, sound: sound)
        } label: {
            HStack(spacing: 4) {
                if timer.mode.hasTimer && (timer.isRunning || timer.remaining < timer.duration(for: timer.phase)) {
                    Image(nsImage: ringIcon(progress: timer.progress))
                    if !timer.hideCountdown { Text(timer.clockText).monospacedDigit() }
                } else {
                    Image(systemName: "leaf")
                }
            }
            .onChange(of: timer.isRunning) { _, _ in syncSound() }
            .onChange(of: timer.phase) { _, _ in syncSound() }
            .onChange(of: timer.mode) { _, _ in syncSound() }
        }
        .menuBarExtraStyle(.window)
    }

    private func syncSound() {
        sound.sync(mode: timer.mode, phase: timer.phase, timerRunning: timer.isRunning)
    }

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
