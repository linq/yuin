import AppKit
import MediaPlayer
import MusicCore

/// Owns the asynchronous cover separately from frequent playback-time updates.
@MainActor final class SystemNowPlaying {
  typealias ImageLoader = (String) async throws -> CGImage
  typealias Sink = ([String: Any]?, MPNowPlayingPlaybackState) -> Void
  private let loadImage: ImageLoader
  private let sink: Sink
  private var requestKey: String?
  private var generation = UUID()
  private var task: Task<Void, Never>?
  private var artwork: MPMediaItemArtwork?
  private var info: [String: Any]?
  private var playbackState = MPNowPlayingPlaybackState.stopped

  init(
    loadImage: @escaping ImageLoader = { try await PlayerArtworkLoader.shared.image(for: $0) },
    sink: @escaping Sink = { info, state in
      let center = MPNowPlayingInfoCenter.default()
      center.nowPlayingInfo = info
      center.playbackState = state
    }
  ) {
    self.loadImage = loadImage
    self.sink = sink
  }

  func update(track: Track?, position: Double, duration: Double, isPlaying: Bool) {
    guard let track else {
      cancel()
      requestKey = nil
      artwork = nil
      info = nil
      playbackState = .stopped
      publish()
      return
    }
    info = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
    ]
    playbackState = isPlaying ? .playing : .paused
    let url = track.artwork.flatMap { $0.isEmpty ? nil : $0 }
    let key = track.id + "\u{0}" + (url ?? "")
    if key != requestKey {
      cancel()
      requestKey = key
      artwork = nil
      if let url {
        let token = generation
        task = Task { [weak self, loadImage] in
          guard let image = try? await loadImage(url), !Task.isCancelled,
            let self, self.generation == token, self.requestKey == key
          else { return }
          let size = NSSize(width: image.width, height: image.height)
          self.artwork = MPMediaItemArtwork(boundsSize: size) { requested in
            NSImage(
              cgImage: image, size: requested.width > 0 && requested.height > 0 ? requested : size)
          }
          self.publish()
        }
      }
    }
    publish()
  }

  func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
  }
  private func publish() {
    var value = info
    if let artwork { value?[MPMediaItemPropertyArtwork] = artwork }
    sink(value, playbackState)
  }
  deinit { task?.cancel() }
}
