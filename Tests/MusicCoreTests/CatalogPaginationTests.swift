import XCTest

@testable import MusicCore

private final class CatalogStub: URLProtocol {
  static var response: ((URLRequest) throws -> Data)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let data = try Self.response!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
final class CatalogPaginationTests: XCTestCase {
  private func catalog() -> MusicCatalog {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CatalogStub.self]
    return MusicCatalog(session: URLSession(configuration: config))
  }
  func testPlaylistSearchMapsPlatformsAndPaginates() async throws {
    for platform in MusicPlatform.allCases {
      CatalogStub.response = { request in
        let params = Dictionary(
          uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        let data: [String: Any]
        switch platform {
        case .kw:
          XCTAssertEqual(params["ft"], "playlist")
          XCTAssertEqual(params["pn"], "1")
          XCTAssertEqual(params["all"], "Queen")
          data = [
            "TOTAL": "61",
            "abslist": [
              [
                "playlistid": "123", "name": "Rock &amp; Live", "nickname": "Author",
                "pic": "https://example.com/a.jpg",
              ]
            ],
          ]
        case .wy:
          XCTAssertEqual(params["type"], "1000")
          XCTAssertEqual(params["offset"], "30")
          data = [
            "code": 200,
            "result": [
              "playlistCount": 61,
              "playlists": [
                [
                  "id": 123, "name": "Rock &amp; Live", "creator": ["nickname": "Author"],
                  "coverImgUrl": "https://example.com/a.jpg",
                ]
              ],
            ],
          ]
        case .kg:
          XCTAssertEqual(params["page"], "2")
          XCTAssertEqual(params["keyword"], "Queen")
          data = [
            "errcode": 0,
            "data": [
              "total": 61,
              "info": [
                [
                  "specialid": 123, "specialname": "Rock &amp; Live", "nickname": "Author",
                  "imgurl": "https://example.com/a.jpg",
                ]
              ],
            ],
          ]
        case .tx:
          XCTAssertEqual(params["page_no"], "1")
          XCTAssertEqual(params["query"], "Queen")
          data = [
            "code": 0,
            "data": [
              "sum": 61,
              "list": [
                [
                  "dissid": "123", "dissname": "Rock &amp; Live", "creator": ["name": "Author"],
                  "imgurl": "https://example.com/a.jpg",
                ]
              ],
            ],
          ]
        case .mg:
          XCTAssertEqual(params["pageNo"], "2")
          XCTAssertEqual(params["text"], "Queen")
          XCTAssertTrue(params["searchSwitch"]!.contains("\"songlist\":1"))
          XCTAssertNotNil(request.value(forHTTPHeaderField: "sign"))
          data = [
            "songListResultData": [
              "totalCount": "61",
              "result": [
                [
                  "id": "123", "name": "Rock &amp; Live", "userName": "Author",
                  "musicListPicUrl": "https://example.com/a.jpg",
                ]
              ],
            ]
          ]
        }
        return try JSONSerialization.data(withJSONObject: data)
      }
      let result = try await catalog().searchCollections("Queen", platform: platform, page: 2)
      XCTAssertEqual(result.total, 61)
      let item = try XCTUnwrap(result.collections.first)
      XCTAssertEqual(item.id, "123")
      XCTAssertEqual(item.title, "Rock & Live")
      XCTAssertEqual(item.subtitle, "Author")
      XCTAssertEqual(item.platform, platform)
      XCTAssertFalse(item.isChart)
    }
  }
  func testPlaylistSearchEmptyResultAndServiceFailureAreDifferent() async throws {
    CatalogStub.response = { _ in
      Data("{\"code\":200,\"result\":{\"playlistCount\":0,\"playlists\":[]}}".utf8)
    }
    let empty = try await catalog().searchCollections("none", platform: .wy)
    XCTAssertTrue(empty.collections.isEmpty)
    XCTAssertEqual(empty.total, 0)
    CatalogStub.response = { _ in Data("{\"code\":403}".utf8) }
    do {
      _ = try await catalog().searchCollections("Queen", platform: .wy)
      XCTFail("Must expose service error")
    } catch { XCTAssertTrue(error.localizedDescription.contains(MusicPlatform.wy.name)) }
  }
  func testQQPlaylistSearchRepairsInvalidTextAndDecodesEntities() async throws {
    CatalogStub.response = { _ in
      let prefix = Data(
        "{\"code\":0,\"data\":{\"sum\":1,\"list\":[{\"dissid\":\"123\",\"dissname\":\"Queen&#32;Live\",\"introduction\":\""
          .utf8)
      let suffix = Data("\"}]}}".utf8)
      return prefix + Data([0xe4]) + suffix
    }
    let result = try await catalog().searchCollections("Queen", platform: .tx)
    XCTAssertEqual(result.collections.first?.title, "Queen Live")
    XCTAssertEqual(result.collections.first?.id, "123")
  }
  func testNeteasePreviewDoesNotReplaceFullPlaylistCountOrOrder() async throws {
    let songs: [[String: Any]] = (1...205).map { ["id": $0, "name": "Song \($0)"] }
    CatalogStub.response = { request in
      let url = try XCTUnwrap(request.url)
      let response: [String: Any]
      if url.path == "/api/playlist/detail" {
        // The legacy endpoint misreports its ten-song preview as a complete playlist.
        response = ["code": 200, "result": ["trackCount": 10, "tracks": Array(songs.prefix(10))]]
      } else if url.path == "/api/v3/playlist/detail" {
        response = [
          "code": 200,
          "playlist": [
            "trackCount": 205,
            "trackIds": (1...205).map { ["id": $0] }, "tracks": Array(songs.prefix(10)),
          ],
        ]
      } else {
        XCTAssertEqual(url.path, "/api/v3/song/detail")
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let raw = try XCTUnwrap(params.first { $0.name == "c" }?.value)
        let ids = try JSONDecoder().decode([[String: Int]].self, from: Data(raw.utf8)).compactMap {
          $0["id"]
        }
        XCTAssertLessThanOrEqual(ids.count, 100)
        // A detail service need not return the playlist's order.
        response = ["code": 200, "songs": ids.reversed().map { songs[$0 - 1] }]
      }
      return try JSONSerialization.data(withJSONObject: response)
    }
    let service = catalog()
    let collection = MusicCollection(id: "large", title: "Large", platform: .wy)
    let first = try await service.tracks(in: collection)
    XCTAssertEqual(first.total, 205)
    XCTAssertEqual(first.tracks.map(\.songID), (1...100).map(String.init))
    let second = try await service.tracks(in: collection, page: 2)
    XCTAssertEqual(second.tracks.map(\.songID), (101...200).map(String.init))
    let all = try await service.allTracks(in: collection)
    XCTAssertEqual(all.map(\.songID), (1...205).map(String.init))
  }
  func testNeteaseMissingSongDetailsCannotBecomeACompleteCopy() async throws {
    CatalogStub.response = { request in
      let data: [String: Any] =
        request.url!.path.contains("playlist")
        ? [
          "code": 200,
          "playlist": ["trackCount": 2, "trackIds": [["id": 1], ["id": 2]], "tracks": []],
        ]
        : ["code": 200, "songs": [["id": 1, "name": "One"]]]
      return try JSONSerialization.data(withJSONObject: data)
    }
    do {
      _ = try await catalog().allTracks(
        in: MusicCollection(id: "partial", title: "Partial", platform: .wy))
      XCTFail("Must not save a partial playlist as complete")
    } catch {
      XCTAssertTrue(error.localizedDescription == L10n.text("网易云列表未完整获取：本页 \(1)/\(2) 首，请重试"))
    }
  }
  func testMiguUsesRealServerPageLimitWithoutSkippingFiftyTracks() async throws {
    CatalogStub.response = { request in
      let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
      let params = Dictionary(
        uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
      let size = Int(params["pageSize"]!)!
      let page = Int(params["pageNo"]!)!
      // Production endpoint limits the returned length to 50, but computes the offset
      // using the requested size. Asking for 100 silently skips half the collection.
      let start = (page - 1) * size
      let end = min(111, start + min(size, 50))
      let songs: [[String: Any]] =
        start < end
        ? (start..<end).map {
          ["songId": "\($0)", "songName": "Song \($0)", "copyrightId": "\($0)"]
        } : []
      return try JSONSerialization.data(withJSONObject: [
        "code": "000000", "data": ["totalCount": songs.isEmpty ? 0 : 111, "songList": songs],
      ])
    }
    let tracks = try await catalog().allTracks(
      in: MusicCollection(id: "test", title: "Test", platform: .mg))
    XCTAssertEqual(tracks.count, 111)
    XCTAssertEqual(Set(tracks.map(\.songID)), Set((0..<111).map(String.init)))
  }
  func testEmptyLastPageCannotEraseKnownTotalAndSilentlySavePartialList() async throws {
    CatalogStub.response = { request in
      let isFirst =
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first {
          $0.name == "pn"
        }!.value == "0"
      let songs: [[String: Any]] = isFirst ? [["id": "1", "name": "One", "artist": "Artist"]] : []
      return try JSONSerialization.data(withJSONObject: [
        "total": isFirst ? 2 : 0, "musiclist": songs,
      ])
    }
    do {
      _ = try await catalog().allTracks(
        in: MusicCollection(id: "test", title: "Test", platform: .kw))
      XCTFail("Incomplete collection must fail, not be saved as a full copy")
    } catch { XCTAssertTrue(error.localizedDescription == L10n.text("列表未完整获取：\(1)/\(2) 首，请重试")) }
  }
}

final class LivePlaylistSearchTests: XCTestCase {
  func testLivePlaylistSearch() async throws {
    guard ProcessInfo.processInfo.environment["MUSIC_PLAYLIST_SEARCH_TESTS"] == "1" else {
      throw XCTSkip("Set MUSIC_PLAYLIST_SEARCH_TESTS=1 to verify online playlist search")
    }
    let catalog = MusicCatalog()
    for platform in MusicPlatform.allCases {
      let page = try await catalog.searchCollections("Queen", platform: platform)
      XCTAssertFalse(page.collections.isEmpty, platform.name)
      XCTAssertGreaterThanOrEqual(page.total, page.collections.count)
      XCTAssertEqual(Set(page.collections.map(\.id)).count, page.collections.count)
      XCTAssertTrue(page.collections.allSatisfy { $0.platform == platform && !$0.isChart })
      print("PLAYLIST_SEARCH \(platform.rawValue): \(page.collections.count)/\(page.total)")
    }
  }
}
