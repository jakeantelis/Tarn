import AVFoundation

/// A soft synthesized bell for breathing sessions. Built in code, so there is no audio file to license.
@MainActor
enum Bell {
    private static var players: [AVAudioPlayer] = []

    /// 16 bit mono WAV of one gentle strike: a warm tone with two quiet overtones and a slow decay.
    static func wavData(frequency: Double = 440, seconds: Double = 3.2, sampleRate: Double = 44100) -> Data {
        let n = Int(seconds * sampleRate)
        var samples = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let attack = min(1, t / 0.012)                     // no click at the start
            let env = attack * exp(-t / 0.95)
            let tone = sin(2 * .pi * frequency * t)
                     + 0.35 * sin(2 * .pi * frequency * 2.0 * t) * exp(-t / 0.5)
                     + 0.18 * sin(2 * .pi * frequency * 2.76 * t) * exp(-t / 0.3)
            samples[i] = Int16(max(-1, min(1, tone * env * 0.42)) * 32767)
        }
        var d = Data()
        func put<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); put(UInt32(36 + n * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(sampleRate)); put(UInt32(sampleRate) * 2); put(UInt16(2)); put(UInt16(16))
        d.append("data".data(using: .ascii)!); put(UInt32(n * 2))
        samples.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    private static let strike = wavData()

    /// Plays `count` strikes, a little over a second apart.
    static func ring(_ count: Int = 1, volume: Float = 0.6) {
        players.removeAll { !$0.isPlaying }
        for i in 0..<max(1, count) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.3) {
                guard let p = try? AVAudioPlayer(data: strike) else { return }
                p.volume = volume
                p.play()
                players.append(p)
            }
        }
    }
}
