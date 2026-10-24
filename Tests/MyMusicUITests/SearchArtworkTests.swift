import AppKit
import MusicCore
import XCTest

@testable import MyMusic

private final class ArtworkDetailStub: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(
      self,
      didLoad: Data(
        #"{"code":200,"songs":[{"id":11,"al":{"picUrl":"https://example.com/cover.jpg"}}]}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@MainActor final class SearchArtworkTests: XCTestCase {
  func testRestoredSearchTrackRepairsArtworkWithoutResettingQueueOrProgress() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = LibraryStore(url: directory.appendingPathComponent("library.json"))
    var state = LibraryState()
    let track = Track(platform: .wy, songID: "11", title: "Search song", artist: "Artist")
    state.queue.replace([track, track], start: 0)
    state.queue.position = 73.7
    state.history = [track]
    var existing = track
    existing.artwork = "https://example.com/existing.jpg"
    state.playlists = [
      LocalPlaylist(name: "Old search results", tracks: [track]),
      LocalPlaylist(name: "Existing cover", tracks: [existing]),
    ]
    try store.save(state)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtworkDetailStub.self]
    let model = AppModel(
      store: store, startServices: false,
      catalog: MusicCatalog(session: URLSession(configuration: configuration)))
    defer {
      model.shutdown()
      try? FileManager.default.removeItem(at: directory)
    }
    model.refreshCurrentArtwork()
    let deadline = ContinuousClock.now + .seconds(3)
    while model.current?.artwork?.isEmpty != false, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(model.current?.artwork, "https://example.com/cover.jpg")
    XCTAssertEqual(model.state.queue.entries.map(\.id), state.queue.entries.map(\.id))
    XCTAssertEqual(model.state.queue.currentID, state.queue.currentID)
    XCTAssertEqual(model.position, 73.7)
    XCTAssertEqual(model.state.queue.position, 73.7)
    XCTAssertEqual(model.state.history.first?.artwork, "https://example.com/cover.jpg")
    XCTAssertEqual(model.state.playlists[0].tracks.first?.artwork, "https://example.com/cover.jpg")
    XCTAssertEqual(model.state.playlists[1].tracks.first?.artwork, existing.artwork)
    XCTAssertEqual(try store.load().queue.current?.artwork, "https://example.com/cover.jpg")
  }

  func testLiveSearchArtworkDecodesThroughTheActualPlayerLoader() async throws {
    guard ProcessInfo.processInfo.environment["MUSIC_ARTWORK_TESTS"] == "1" else {
      throw XCTSkip("Set MUSIC_ARTWORK_TESTS=1 to verify live player artwork decoding")
    }
    let page = try await MusicCatalog().search("红颜", platform: .wy)
    let url = try XCTUnwrap(page.tracks.first?.artwork)
    let image = try await PlayerArtworkLoader.shared.image(for: url)
    XCTAssertGreaterThan(image.width, 0)
    XCTAssertGreaterThan(image.height, 0)
    print("SEARCH_PLAYER_ARTWORK decoded=\(image.width)x\(image.height)")
  }
}
