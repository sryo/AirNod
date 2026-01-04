// Plays silent audio to keep AirPods motion active.

import AVFoundation

final class AudioLooper {
    private var audioPlayer: AVAudioPlayer?

    init() {
        setupPlayer()
    }

    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Infinite loop
            audioPlayer?.volume = 0.01 // Barely audible
            audioPlayer?.prepareToPlay()
        } catch {
            // Audio looper is optional - app still functions without it
        }
    }

    func start() {
        audioPlayer?.play()
    }

    func stop() {
        audioPlayer?.stop()
    }
}
