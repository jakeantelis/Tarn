import SwiftUI

struct ContentView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var sound: SoundEngine
    @State private var tab = 0
    private var effectiveTab: Int { timer.mode.hasTimer ? tab : max(tab, 1) }

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: Binding(get: { timer.mode }, set: { timer.setMode($0) })) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("", selection: Binding(get: { effectiveTab }, set: { tab = $0 })) {
                if timer.mode.hasTimer { Text("Timer").tag(0) }
                Text("Breathe").tag(1)
                Text("Sounds").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch effectiveTab {
            case 0: TimerTab(timer: timer)
            case 1: BreathingView()
            default: MixerTab(sound: sound)
            }

            HStack {
                Button {
                    sound.toggle()
                } label: {
                    Label(sound.isPlaying ? "Sounds on" : "Sounds off",
                          systemImage: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct TimerTab: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(timer.phase.isBreak ? Color.teal : Color.orange,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.progress)
                VStack(spacing: 2) {
                    Text(timer.clockText)
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(timer.phase.rawValue)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, height: 170)

            HStack(spacing: 10) {
                Button(timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])
                Button("Reset") { timer.reset() }
                Button("Skip") { timer.skip() }
            }

            Text("Round \(timer.completedRounds % timer.mode.roundsPerSet + 1) of \(timer.mode.roundsPerSet)  ·  \(timer.completedRounds) done today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MixerTab: View {
    @ObservedObject var sound: SoundEngine

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Soundscape.allCases) { s in
                HStack(spacing: 10) {
                    Image(systemName: s.symbol).frame(width: 20).foregroundStyle(.secondary)
                    Text(s.title).frame(width: 52, alignment: .leading)
                    Slider(value: Binding(get: { sound.levels[s] ?? 0 },
                                          set: { v in
                                              sound.setLevel(v, for: s)
                                              if v > 0 && !sound.isPlaying { sound.play() }
                                          }), in: 0...1)
                }
                .font(.callout)
            }
        }
        .frame(minHeight: 190, alignment: .top)
    }
}
