import SwiftUI
import AppKit

/// A roomy Settings window with a sidebar, instead of a long scrolling box in the popover.
@MainActor
final class SettingsWindowOpener {
    static let shared = SettingsWindowOpener()
    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    func show(_ section: SettingsSection = .focus) {
        navigation.section = section
        if window == nil {
            let model = AppModel.shared
            let host = NSHostingView(rootView: SettingsWindowView(navigation: navigation, timer: model.timer, sound: model.sound))
            host.sizingOptions = []          // the window decides the size, never the content
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Tarn Settings"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 580, height: 500)
            w.contentView = host
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var section: SettingsSection = .focus
}

struct SettingsWindowView: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    @AppStorage("focusPalette") private var paletteKey = "red"

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsSection.allCases) { s in
                    Button { navigation.section = s } label: {
                        Label(s.rawValue, systemImage: s.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(navigation.section == s ? Color.accentColor.opacity(0.28) : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(navigation.section == s ? .isSelected : [])
                }
                Spacer()
                Text("Tarn \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            .padding(14)
            .frame(width: 190)
            .background(Color.black.opacity(0.12))

            ScrollView {
                SettingsTab(timer: timer, sound: sound, section: navigation.section)
                    .padding(28)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .tint(navigation.section == .breathe ? Color.breatheTint : (FocusPalette.all[paletteKey]?.tint ?? Color.focusTint))
    }
}
