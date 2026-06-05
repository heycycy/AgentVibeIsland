import AppKit

/// Sound engine for Agent Vibe Island.
/// Uses NSSound for safe playback — never crashes even without audio hardware.
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

    private init() {}

    // MARK: - Public API

    func playNewRequest() {
        guard !isMuted else { return }
        playSystemSound("Tink", volume: volumeNewRequest)
    }

    func playAllow() {
        guard !isMuted else { return }
        playSystemSound("Glass", volume: volumeAllow)
    }

    func playDeny() {
        guard !isMuted else { return }
        playSystemSound("Basso", volume: volumeDeny)
    }

    // MARK: - Internals

    // TODO: Replace system sounds with custom synthesized tones once a crash-safe audio API is available
    private func playSystemSound(_ name: String, volume: Float) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = volume / 100.0
        sound.play()
    }
}
