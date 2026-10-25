import AppKit
import MediaPlayer
import MusicCore
import XCTest

@testable import MyMusic

@MainActor final class SystemNowPlayingTests: XCTestCase {
  func testCoverTasksCannotOverwriteNewTrackAndTimeUpdatesDoNotReload() async throws {
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    let image = try XCTUnwrap(bitmap.cgImage)
    var pending: [String: CheckedContinuation<CGImage, Error>] = [:]
    var loads: [String] = []
    var info: [String: Any]?
    var state = MPNowPlayingPlaybackState.stopped
    let publisher = SystemNowPlaying(
      loadImage: { url in
        loads.append(url)
        return try await withCheckedThrowingContinuation { pending[url] = $0 }
      },
      sink: {
        info = $0
        state = $1
      })
    let first = Track(
      platform: .wy, songID: "first", title: "First", artist: "Artist",
      artwork: "https://example.com/first.png")
    let next = Track(
      platform: .wy, songID: "next", title: "Next", artist: "Artist",
      artwork: "https://example.com/next.png")
    publisher.update(track: first, position: 0, duration: 180, isPlaying: true)
    await Task.yield()
    publisher.update(track: next, position: 0, duration: 200, isPlaying: true)
    await Task.yield()
    for position in 1...10 {
      publisher.update(track: next, position: Double(position), duration: 200, isPlaying: false)
    }
    XCTAssertEqual(
      loads.count, 2, "Load only once per track/URL, not on each timer or pause update")
    try XCTUnwrap(pending.removeValue(forKey: next.artwork!)).resume(returning: image)
    for _ in 0..<4 { await Task.yield() }
    let artwork = try XCTUnwrap(info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
    XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "Next")
    XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 10)
    XCTAssertEqual(state, .paused)
    try XCTUnwrap(pending.removeValue(forKey: first.artwork!)).resume(returning: image)
    for _ in 0..<4 { await Task.yield() }
    XCTAssertTrue((info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork) === artwork)
    XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "Next")
    let noCover = Track(platform: .wy, songID: "none", title: "No cover", artist: "Artist")
    publisher.update(track: noCover, position: 0, duration: 60, isPlaying: true)
    XCTAssertNil(
      info?[MPMediaItemPropertyArtwork],
      "Do not reuse a previous song's cover for a coverless track")
    publisher.update(track: nil, position: 0, duration: 0, isPlaying: false)
    XCTAssertNil(info)
    XCTAssertEqual(state, .stopped)
  }

  func testAppPublishesDecodedCoverToSystemPlayer() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    let pixels = try XCTUnwrap(bitmap.bitmapData)
    for y in 0..<8 {
      for x in 0..<8 {
        let offset = y * bitmap.bytesPerRow + x * 4
        pixels[offset] = 255
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 255
      }
    }
    let url = directory.appendingPathComponent("cover.png")
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    defer { model.shutdown() }
    let center = MPNowPlayingInfoCenter.default()
    let originalInfo = center.nowPlayingInfo
    let originalState = center.playbackState
    defer {
      center.nowPlayingInfo = originalInfo
      center.playbackState = originalState
    }
    model.state.queue.replace(
      [
        Track(
          platform: .wy, songID: "cover", title: "Cover song", artist: "Artist", duration: 180,
          artwork: url.absoluteString)
      ], start: 0)
    model.pausePlayback()
    let deadline = ContinuousClock.now + .seconds(2)
    while center.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil, ContinuousClock.now < deadline
    {
      try await Task.sleep(for: .milliseconds(10))
    }
    let artwork = try XCTUnwrap(
      center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
      "The macOS player must receive a real cover, rather than fall back to the app icon")
    let publishedImage = try XCTUnwrap(artwork.image(at: NSSize(width: 64, height: 64)))
    let publishedBitmap = try XCTUnwrap(
      NSBitmapImageRep(data: try XCTUnwrap(publishedImage.tiffRepresentation)))
    let color = try XCTUnwrap(publishedBitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
    // TIFF drawing can convert the device profile; verify the opaque red
    // fixture survives that conversion instead of assuming identical RGB bytes.
    XCTAssertGreaterThan(color.redComponent, 0.9)
    XCTAssertGreaterThan(color.redComponent, color.greenComponent * 3)
    XCTAssertGreaterThan(color.redComponent, color.blueComponent * 3)
    XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.02)
    model.updatePlaybackTime(position: 42, duration: 180)
    model.pausePlayback()
    XCTAssertNotNil(
      center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
      "Metadata/time refreshes must preserve the current cover")
    XCTAssertEqual(
      center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 42)
  }
}
