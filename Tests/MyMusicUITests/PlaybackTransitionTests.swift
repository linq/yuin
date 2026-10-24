import AVFoundation
import MusicCore
import XCTest

@testable import MyMusic

@MainActor final class PlaybackTransitionTests: XCTestCase {
  @MainActor private final class Resolver {
    let file: URL
    var calls: [String] = []
    var pending: CheckedContinuation<URL, Error>?
    init(file: URL) { self.file = file }
    func resolve(_ track: Track, quality: String) async throws -> URL {
      calls.append("\(track.songID):\(quality)")
      if track.songID == "b", quality == "320k" {
        return try await withCheckedThrowingContinuation { pending = $0 }
      }
      return file
    }
    func release() {
      pending?.resume(returning: file)
      pending = nil
    }
  }

  private func fixture() throws -> (URL, AppModel, AVPlayer, Resolver, [Track]) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("silence.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160_000)!
    buffer.frameLength = 160_000
    buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
    try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    let resolver = Resolver(file: url)
    let player = AVPlayer()
    player.isMuted = true
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false, player: player,
      audioURLResolver: { track, quality in try await resolver.resolve(track, quality: quality) })
    model.sourceReady = true
    model.setVolume(1)
    model.capabilities = try JSONDecoder().decode(
      [String: SourceCapability].self,
      from: Data(#"{"wy":{"type":"music","actions":["musicUrl"],"qualitys":["128k","320k"]}}"#.utf8)
    )
    let tracks = ["a", "b", "c"].map {
      Track(platform: .wy, songID: $0, title: $0, artist: "Fixture", duration: 20)
    }
    return (directory, model, player, resolver, tracks)
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "Timed out waiting for local playback")
  }

  func testSwitchKeepsOutgoingItemUntilReplacementIsPrepared() async throws {
    let (directory, model, player, resolver, tracks) = try fixture()
    defer {
      resolver.release()
      model.shutdown()
      try? FileManager.default.removeItem(at: directory)
    }
    model.play(tracks[0], in: tracks)
    try await waitUntil { player.rate > 0 && !model.isLoadingAudio && player.volume > 0.99 }
    let outgoing = try XCTUnwrap(player.currentItem)
    model.next()
    XCTAssertTrue(
      player.currentItem === outgoing,
      "Do not tear down the current item before resolving its replacement")
    try await waitUntil { resolver.pending != nil }
    XCTAssertTrue(player.currentItem === outgoing)
    try await waitUntil { player.volume < 0.99 }
    XCTAssertEqual(model.state.volume, 1, "The envelope must not change the saved volume")
    resolver.release()
    try await waitUntil {
      player.currentItem !== outgoing && player.rate > 0 && !model.isLoadingAudio
    }
    XCTAssertEqual(model.current?.songID, "b")
    XCTAssertEqual(resolver.calls.filter { $0 == "b:320k" }.count, 1)
    try await waitUntil { player.volume > 0.99 }
  }

  func testNextTrackIsPreparedAndQualityChangesDiscardTheOldPreparation() async throws {
    let (directory, model, player, resolver, tracks) = try fixture()
    defer {
      resolver.release()
      model.shutdown()
      try? FileManager.default.removeItem(at: directory)
    }
    model.play(tracks[0], in: tracks)
    try await waitUntil { player.rate > 0 && !model.isLoadingAudio }
    try await waitUntil { resolver.pending != nil }
    XCTAssertEqual(model.current?.songID, "a", "Preloading must not change the current track")
    XCTAssertEqual(model.state.history.map(\.songID), ["a"])
    model.state.playbackQuality = "128k"
    model.next()
    try await waitUntil { model.nowQuality == "128k" && player.rate > 0 && !model.isLoadingAudio }
    XCTAssertTrue(resolver.calls.contains("b:128k"))
    resolver.release()
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(model.nowQuality, "128k", "A stale preload must not replace the chosen quality")
  }

  func testCancellingPreparedHandoffDoesNotRestartEitherTrack() async throws {
    let (directory, model, player, resolver, tracks) = try fixture()
    defer {
      resolver.release()
      model.shutdown()
      try? FileManager.default.removeItem(at: directory)
    }
    model.play(tracks[0], in: tracks)
    try await waitUntil { player.rate > 0 && !model.isLoadingAudio }
    model.next()
    try await waitUntil { resolver.pending != nil }
    model.togglePlayback()
    resolver.release()
    try await Task.sleep(for: .milliseconds(250))
    XCTAssertNil(player.currentItem)
    XCTAssertEqual(player.rate, 0)
    XCTAssertFalse(model.isLoadingAudio)
    XCTAssertFalse(model.isPlaying)
  }

  func testRapidSkipCannotBeOverwrittenByAnEarlierResolve() async throws {
    let (directory, model, player, resolver, tracks) = try fixture()
    defer {
      resolver.release()
      model.shutdown()
      try? FileManager.default.removeItem(at: directory)
    }
    model.play(tracks[0], in: tracks)
    try await waitUntil { player.rate > 0 && !model.isLoadingAudio }
    model.next()
    try await waitUntil { resolver.pending != nil }
    model.next()
    try await waitUntil { model.current?.songID == "c" && player.rate > 0 && !model.isLoadingAudio }
    let latest = player.currentItem
    resolver.release()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertTrue(player.currentItem === latest)
    XCTAssertEqual(model.state.history.first?.songID, "c")
  }

  func testNaturalTrackEndUsesThePreparedNextTrackWithoutLeakingOldProgress() async throws {
    let (directory, model, player, resolver, tracks) = try fixture()
    defer {
      resolver.release()
      model.shutdown()
      try? FileManager.default.removeItem(at: directory)
    }
    model.play(tracks[0], in: tracks)
    try await waitUntil { player.rate > 0 && !model.isLoadingAudio && resolver.pending != nil }
    resolver.release()
    await player.seek(
      to: CMTime(seconds: 19.95, preferredTimescale: 600), toleranceBefore: .zero,
      toleranceAfter: .zero)
    try await waitUntil { model.current?.songID == "b" && player.rate > 0 && !model.isLoadingAudio }
    XCTAssertEqual(resolver.calls.filter { $0 == "b:320k" }.count, 1)
    XCTAssertLessThan(model.position, 2, "The new song must not inherit the outgoing timestamp")
    XCTAssertEqual(model.state.history.prefix(2).map(\.songID), ["b", "a"])
  }
}
