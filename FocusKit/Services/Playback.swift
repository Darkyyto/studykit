import AVFoundation
import Observation

@MainActor
@Observable
final class Playback {
    private(set) var url: URL?
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var completion: Task<Void, Never>?

    var currentTime: TimeInterval {
        player?.currentTime ?? 0
    }

    func load(_ url: URL) {
        guard self.url != url else { return }
        stop()
        self.url = url
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        watchForEnd()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        completion?.cancel()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        if isPlaying { watchForEnd() }
    }

    func stop() {
        player?.stop()
        player = nil
        url = nil
        isPlaying = false
        duration = 0
        completion?.cancel()
    }

    private func watchForEnd() {
        completion?.cancel()
        guard let player else { return }
        let remaining = player.duration - player.currentTime
        completion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining + 0.05))
            guard !Task.isCancelled, let self, self.player?.isPlaying == false else { return }
            self.isPlaying = false
            self.player?.currentTime = 0
        }
    }
}
