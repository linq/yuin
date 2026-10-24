import AVFoundation
import XCTest

@testable import MusicCore

/// Opt-in acceptance test. User-provided scripts and downloaded audio are never committed.
@MainActor final class RealSourceTests: XCTestCase {
  func testRealSourcePlaybackAndDownload() async throws {
    guard let location = ProcessInfo.processInfo.environment["MUSIC_REAL_SOURCE"] else {
      throw XCTSkip("Set MUSIC_REAL_SOURCE to a trusted source URL or local path")
    }
    let source: SourceRecord
    if location.hasPrefix("https://") || location.hasPrefix("http://") {
      source = try await SourceImport.online(location)
    } else {
      source = try SourceImport.local(URL(fileURLWithPath: location))
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let host = try XCTUnwrap(
      [".build/debug/MusicSourceHost", ".build/out/Products/Debug/MusicSourceHost"]
        .map { root.appendingPathComponent($0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) })
    let runtime = SourceRuntime()
    defer { runtime.stop() }
    try await runtime.start(source, executable: host)
    print("REAL SOURCE \(source.name) \(source.version): \(runtime.capabilities.keys.sorted())")
    let catalog = MusicCatalog()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var downloaded: [URL] = []
    var playable = 0
    for platform in MusicPlatform.allCases {
      if let only = ProcessInfo.processInfo.environment["MUSIC_REAL_PLATFORM"],
        only != platform.rawValue
      {
        continue
      }
      guard runtime.capabilities[platform.rawValue] != nil else { continue }
      do {
        let query = ProcessInfo.processInfo.environment["MUSIC_REAL_QUERY"] ?? "晴天"
        let results = try await catalog.search(query, platform: platform)
        let track = try XCTUnwrap(results.tracks.first)
        let qualities =
          ProcessInfo.processInfo.environment["MUSIC_REAL_ALL_QUALITIES"] == "1"
          ? runtime.capabilities[platform.rawValue]!.qualitys : ["320k"]
        for quality in qualities {
          do {
            let url = try await runtime.resolve(track, quality: quality)
            print("REAL \(platform.rawValue) \(quality) resolved \(track.title) / \(track.artist)")
            try await assertPlayback(url)
            playable += 1
            print("REAL \(platform.rawValue) \(quality) streaming PASS")
            if downloaded.isEmpty
              || ProcessInfo.processInfo.environment["MUSIC_REAL_DOWNLOAD_ALL"] == "1"
            {
              let file = try await DownloadService.download(
                url, track: track, quality: quality, directory: directory
              ) { _ in }
              downloaded.append(file.url)
              let duration = try await AVURLAsset(url: file.url).load(.duration).seconds
              let bytes = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
              print(
                "REAL \(platform.rawValue) \(quality) download PASS: \(file.url.pathExtension), \(Int(duration))s, \(bytes) bytes"
              )
            }
          } catch {
            print("REAL \(platform.rawValue) \(quality) unavailable: \(redacted(error))")
          }
        }
      } catch {
        print("REAL \(platform.rawValue) unavailable: \(redacted(error))")
      }
    }
    XCTAssertGreaterThan(playable, 0, "At least one platform must actually play")
    XCTAssertFalse(downloaded.isEmpty, "At least one real download must succeed")
    runtime.stop()
    for local in downloaded { try await assertPlayback(local) }
    print("REAL offline playback PASS for \(downloaded.count) files with source stopped")
  }

  private func redacted(_ error: Error) -> String {
    // Source errors may include access tokens.
    error.localizedDescription.replacingOccurrences(
      of: "https?://[^\\s]+", with: "[URL]", options: .regularExpression)
  }

  private func assertPlayback(_ url: URL) async throws {
    let player = AVPlayer(url: url)
    player.isMuted = true
    player.play()
    defer {
      player.pause()
      player.replaceCurrentItem(with: nil)
    }
    for _ in 0..<150 {
      if player.currentTime().seconds > 0.2 { return }
      if let error = player.currentItem?.error { throw error }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw MusicError.message("AVPlayer did not advance within 15 seconds")
  }
}
