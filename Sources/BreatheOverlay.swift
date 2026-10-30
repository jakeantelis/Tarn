import SwiftUI
import AppKit

/// Full screen, distraction free breathing. Optionally hides other apps and restores them on exit.
@MainActor
final class BreatheOverlay {
    static let shared = BreatheOverlay()
    private var windows: [NSWindow] = []
    private var hidden: [NSRunningApplication] = []
    private var monitor: Any?

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        guard !isShowing else { return }
        if UserDefaults.standard.object(forKey: "hideOthersWhenBreathing") as? Bool ?? true {
            hidden = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && !$0.isHidden && $0 != NSRunningApplication.current
            }
            hidden.forEach { $0.hide() }
        }
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.backgroundColor = .clear
            w.isOpaque = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: OverlayView(onClose: { [weak self] in self?.close() }))
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.close(); return nil }   // Esc
            return e
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; ws.forEach { $0.animator().alphaValue = 0 } },
                                             completionHandler: { ws.forEach { $0.orderOut(nil) } })
        hidden.forEach { $0.unhide() }
        hidden = []
        VoiceGuide.shared.reset()
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct OverlayView: View {
    let onClose: () -> Void
    @AppStorage("guideMe") private var guideMe = false
    @AppStorage("breathStyle") private var styleRaw = BreathStyle.bloom.rawValue
    @State private var start = Date()
    private let pattern = BreathPattern.settle

    var body: some View {
        ZStack {
            // Fully covers the desktop (icons, windows and wallpaper) with a calm dusk gradient.
            LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24), Color(red: 0.04, green: 0.06, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(0.97)
                .ignoresSafeArea()
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                let s = pattern.state(at: t)
                VStack(spacing: 28) {
                    ZStack {
                        switch BreathStyle(rawValue: styleRaw) ?? .bloom {
                        case .fill: FillCanvas(scale: s.scale, time: t)
                        case .bloom: BloomCanvas(scale: s.scale, time: t)
                        case .rings: RingsCanvas(scale: s.scale, time: t)
                        }
                    }
                    .frame(width: 460, height: 460)
                    Text(s.label)
                        .font(.system(size: 34, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    if guideMe {
                        Text(Guidance.line(at: t))
                            .font(.system(size: 17, weight: .light, design: .serif).italic())
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(height: 24)
                            .id(Guidance.index(at: t))
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 1.2), value: Guidance.index(at: t))
                    }
                }
                .onChange(of: s.label) { _, new in VoiceGuide.shared.cue(new) }
                .onChange(of: Guidance.index(at: t)) { _, _ in if guideMe { VoiceGuide.shared.say(Guidance.line(at: t)) } }
            }
            VStack {
                Spacer()
                Text("Press Esc or click anywhere to leave")
                    .font(.footnote).foregroundStyle(.white.opacity(0.35)).padding(.bottom, 28)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .preferredColorScheme(.dark)
    }
}
