import AVFoundation
import Foundation
import MusicCore

/// One speculative next track, shared with the foreground request on a handoff.
/// A source, quality, file or queue-entry change always starts a fresh preparation.
@MainActor final class AudioPreparation {
  struct Key: Equatable {
    let entry: UUID
    let source: UUID
    let quality: String
    let file: URL?
  }
  struct Audio {
    let asset: AVURLAsset
    let quality: String
  }
  private var key: Key?
  private var task: Task<Audio, Error>?
  private var generation = UUID()
  private var created = ContinuousClock.now

  func prepare(
    _ key: Key, resolve: @escaping @MainActor () async throws -> URL
  ) -> Task<Audio, Error> {
    if self.key == key, let task, ContinuousClock.now - created < .seconds(60) { return task }
    cancel()
    self.key = key
    created = .now
    let generation = self.generation
    let task = Task { [weak self] in
      do {
        let url = try await resolve()
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
          throw MusicError.message(L10n.text("当前系统无法播放此音频格式"))
        }
        try Task.checkCancellation()
        return Audio(asset: asset, quality: key.quality)
      } catch {
        // A failed speculative request must not poison the next foreground retry.
        if self?.generation == generation {
          self?.key = nil
          self?.task = nil
        }
        throw error
      }
    }
    self.task = task
    return task
  }

  func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
    key = nil
  }
}
