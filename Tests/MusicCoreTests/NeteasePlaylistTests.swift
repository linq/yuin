import XCTest

@testable import MusicCore

final class NeteasePlaylistTests: XCTestCase {
  func testLiveSearchedPlaylistIsNotTruncatedToTenTracks() async throws {
    guard ProcessInfo.processInfo.environment["MUSIC_NETEASE_PLAYLIST_TESTS"] == "1" else {
      throw XCTSkip("Set MUSIC_NETEASE_PLAYLIST_TESTS=1 to verify complete NetEase playlists")
    }
    let catalog = MusicCatalog()
    let search = try await catalog.searchCollections("赖导", platform: .wy)
    let item = try XCTUnwrap(search.collections.first)
    let page = try await catalog.tracks(in: item)
    print("NETEASE_PLAYLIST id=\(item.id) page=\(page.tracks.count) total=\(page.total)")
    XCTAssertGreaterThan(
      page.total, 10,
      "Known large searched playlist must not report the ten-track preview as its total")
    XCTAssertGreaterThan(page.tracks.count, 10)
    let all = try await catalog.allTracks(in: item)
    XCTAssertEqual(all.count, page.total)
    XCTAssertEqual(Set(all.map(\.id)).count, all.count)
  }
  func testLiveRecommendationsAndChartsUseCompleteIDs() async throws {
    guard ProcessInfo.processInfo.environment["MUSIC_NETEASE_PLAYLIST_TESTS"] == "1" else {
      throw XCTSkip("Set MUSIC_NETEASE_PLAYLIST_TESTS=1 to verify complete NetEase playlists")
    }
    let catalog = MusicCatalog()
    for charts in [false, true] {
      let collections = try await catalog.collections(platform: .wy, charts: charts)
      let item = try XCTUnwrap(collections.first)
      let page = try await catalog.tracks(in: item)
      let all = try await catalog.allTracks(in: item)
      XCTAssertGreaterThan(page.total, 10)
      XCTAssertEqual(all.count, page.total)
      XCTAssertEqual(all.prefix(100).map(\.id), page.tracks.map(\.id))
      print("NETEASE_COMPLETE chart=\(charts) id=\(item.id) fetched=\(all.count)/\(page.total)")
    }
  }

}
