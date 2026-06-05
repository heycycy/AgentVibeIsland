import AVFoundation

/// Synthesized sound engine for Agent Vibe Island.
/// All sounds are generated in real-time using AVAudioEngine — no asset files.
final class AudioEngine {

    static let shared = AudioEngine()

    var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: "audioMuted") }
        set { UserDefaults.standard.set(newValue, forKey: "audioMuted") }
    }

    var volumeNewRequest: Float {
        get { UserDefaults.standard.object(forKey: "volumeNewRequest") as? Float ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: "volumeNewRequest") }
    }

    var volumeAllow: Float {
        get { UserDefaults.standard.object(forKey: "volumeAllow") as? Float ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: "volumeAllow") }
    }

    var volumeDeny: Float {
        get { UserDefaults.standard.object(forKey: "volumeDeny") as? Float ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: "volumeDeny") }
    }

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 44100

    private init() {
        try? engine.start()
    }

    // MARK: - Public API

    /// Sine sweep 620→400 Hz, 90 ms, gain 0.22→0.
    func playNewRequest() {
        guard !isMuted else { return }
        let vol = volumeNewRequest / 100.0
        let duration = 0.09
        let frameCount = Int(duration * sampleRate)
        let buffer = makeBuffer(frameCount: frameCount)
        let data = buffer.floatChannelData![0]
        let dt = 1.0 / sampleRate

        var phase = 0.0
        for i in 0..<frameCount {
            let t = Double(i) * dt
            let freq = 620.0 - 220.0 * (t / duration)
            let gain = Float(0.22 * (1.0 - t / duration)) * vol
            data[i] = gain * sinf(Float(2.0 * .pi * phase))
            phase += freq * dt
        }
        play(buffer)
    }

    /// Two sine tones: 880 Hz then 1100 Hz, 100 ms each, 70 ms apart, gain 0.15→0.
    func playAllow() {
        guard !isMuted else { return }
        let vol = volumeAllow / 100.0
        let toneDur = 0.10
        let gap = 0.07
        let totalDuration = toneDur + gap + toneDur
        let frameCount = Int(totalDuration * sampleRate)
        let buffer = makeBuffer(frameCount: frameCount)
        let data = buffer.floatChannelData![0]
        let dt = 1.0 / sampleRate

        var phase = 0.0
        for i in 0..<frameCount {
            let t = Double(i) * dt
            if t < toneDur {
                let gain = Float(0.15 * (1.0 - t / toneDur)) * vol
                data[i] = gain * sinf(Float(2.0 * .pi * phase))
                phase += 880.0 * dt
            } else if t < toneDur + gap {
                data[i] = 0
                phase = 0 // reset phase for clean second tone
            } else {
                let t2 = t - toneDur - gap
                let gain = Float(0.15 * (1.0 - t2 / toneDur)) * vol
                data[i] = gain * sinf(Float(2.0 * .pi * phase))
                phase += 1100.0 * dt
            }
        }
        play(buffer)
    }

    /// Triangle wave sweep 160→100 Hz, 140 ms, gain 0.25→0.
    func playDeny() {
        guard !isMuted else { return }
        let vol = volumeDeny / 100.0
        let duration = 0.14
        let frameCount = Int(duration * sampleRate)
        let buffer = makeBuffer(frameCount: frameCount)
        let data = buffer.floatChannelData![0]
        let dt = 1.0 / sampleRate

        var phase = 0.0
        for i in 0..<frameCount {
            let t = Double(i) * dt
            let freq = 160.0 - 60.0 * (t / duration)
            let gain = Float(0.25 * (1.0 - t / duration)) * vol
            // Triangle: 2|2·frac(phase) - 1| - 1
            let frac = phase - Double(Int(phase))
            let triangle = Float(2.0 * abs(2.0 * frac - 1.0) - 1.0)
            data[i] = gain * triangle
            phase += freq * dt
        }
        play(buffer)
    }

    // MARK: - Internals

    private func makeBuffer(frameCount: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)

        if !engine.isRunning {
            try? engine.start()
        }

        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.engine.disconnectNodeOutput(player)
                self?.engine.detach(player)
            }
        }
        player.play()
    }
}
