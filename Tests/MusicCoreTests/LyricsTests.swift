import Foundation
import XCTest
import zlib

@testable import MusicCore

private final class LyricsStub: URLProtocol {
  static var respond: ((URLRequest) throws -> Data)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let data = try Self.respond!(request)
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
final class LyricsTests: XCTestCase {
  private func service(cache: URL? = nil) -> LyricsService {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LyricsStub.self]
    return LyricsService(session: URLSession(configuration: config), cacheDirectory: cache)
  }
  private func track(_ platform: MusicPlatform, info: [String: JSONValue] = [:]) -> Track {
    Track(
      platform: platform, songID: "123", title: "Test", artist: "Artist", duration: 60,
      sourceInfo: info)
  }
  private func json(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value)
  }
  private func compressed(_ text: String) -> Data {
    let data = Data(text.utf8)
    var size = compressBound(uLong(data.count))
    var out = Data(count: Int(size))
    let status = out.withUnsafeMutableBytes { o in
      data.withUnsafeBytes { i in
        compress(
          o.bindMemory(to: Bytef.self).baseAddress, &size, i.bindMemory(to: Bytef.self).baseAddress,
          uLong(data.count))
      }
    }
    XCTAssertEqual(status, Z_OK)
    out.count = Int(size)
    return out
  }
  func testLRCMultiTagsOffsetsTranslationAndSeekBoundaries() {
    let doc = LyricsDocument.parse(
      "[ar:Artist]\n[00:03.00]B\n[00:01.25][00:02.125]A\n[offset:500]",
      translation: "[offset:500]\n[00:01.25]译文")
    XCTAssertEqual(doc.lines.map(\.time), [0.75, 1.625, 2.5])
    XCTAssertEqual(doc.lines.map(\.text), ["A", "A", "B"])
    XCTAssertEqual(doc.lines[0].translation, "译文")
    XCTAssertNil(doc.activeLine(at: 0.74))
    XCTAssertEqual(doc.activeLine(at: 0.75), 0)
    XCTAssertEqual(doc.activeLine(at: 2), 1)
    XCTAssertEqual(doc.activeLine(at: 999), 2)
    XCTAssertEqual(doc.activeLine(at: 0.8), 0, "Seeking backwards must select the earlier line")
    XCTAssertNil(doc.activeLine(at: .nan))
  }
  func testDuplicateTimesWordTagsAndInstrumentalGaps() {
    let doc = LyricsDocument.parse(
      "[00:01]First\n[00:01]译文\n[00:02]\n[3000,1000]<0,500,0>A<500,500,0>B")
    XCTAssertEqual(doc.lines.map(\.text), ["First\n译文", "", "AB"])
    XCTAssertEqual(doc.lines.map(\.time), [1, 2, 3])
    XCTAssertEqual(doc.activeLine(at: 2.5), 1)
  }
  func testPlainLyricsAndEmptyDocuments() {
    let doc = LyricsDocument.parse("[ti:Title]\nFirst line\nSecond line")
    XCTAssertFalse(doc.isTimed)
    XCTAssertEqual(doc.plainText, "First line\nSecond line")
    XCTAssertTrue(LyricsDocument.parse("[ar:Artist]\n").isEmpty)
    XCTAssertTrue(LyricsDocument.parse("<html><body>Gateway error</body></html>").isEmpty)
  }
  func testNeteaseUsesSongIdentityAndCachesForOfflineReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var calls = 0
    LyricsStub.respond = { request in
      calls += 1
      XCTAssertEqual(request.url?.host, "music.163.com")
      XCTAssertEqual(
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
          $0.name == "id"
        }?.value, "123")
      return try self.json([
        "code": 200, "lrc": ["lyric": "[00:01]Original"], "tlyric": ["lyric": "[00:01]译文"],
      ])
    }
    let first = try await service(cache: directory).lyrics(for: track(.wy))
    XCTAssertEqual(first.lines[0].translation, "译文")
    LyricsStub.respond = { _ in
      XCTFail("Cached lyrics should work offline")
      throw URLError(.notConnectedToInternet)
    }
    let second = try await service(cache: directory).lyrics(for: track(.wy))
    XCTAssertEqual(first, second)
    XCTAssertEqual(calls, 1)
  }
  func testKuwoCompressedLyrics() async throws {
    LyricsStub.respond = { request in
      XCTAssertTrue(request.url!.absoluteString.contains("lrcx=0"))
      return Data("tp=content\r\n\r\n".utf8) + self.compressed("[00:01.20]Kuwo")
    }
    let document = try await service().lyrics(for: track(.kw))
    XCTAssertEqual(document.lines.first?.time, 1.2)
    XCTAssertEqual(document.lines.first?.text, "Kuwo")
  }
  func testKuwoHonorsReturnedEncodingWhenServerIgnoresRequestedFormat() async throws {
    let key = Array("yeelion".utf8)
    let encoded = Data(
      Data("[00:01]<0,500>Encoded".utf8).enumerated().map {
        $0.element ^ key[$0.offset % key.count]
      }
    ).base64EncodedString()
    LyricsStub.respond = { _ in Data("TP=content\r\nlrcx=1\r\n\r\n".utf8) + self.compressed(encoded)
    }
    let document = try await service().lyrics(for: track(.kw))
    XCTAssertEqual(document.lines.first?.text, "Encoded")
  }
  func testQQDecodesBase64AndEntities() async throws {
    LyricsStub.respond = { request in
      XCTAssertEqual(
        request.value(forHTTPHeaderField: "Referer"), "https://y.qq.com/portal/player.html")
      return try self.json([
        "code": 0, "lyric": Data("[00:01]A &amp; B &#x4e2d;".utf8).base64EncodedString(),
      ])
    }
    let document = try await service().lyrics(for: track(.tx))
    XCTAssertEqual(document.lines.first?.text, "A & B 中")
  }
  func testKugouHashLookupAndKRCFallback() async throws {
    let key: [UInt8] = [
      0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e,
      0x69,
    ]
    let payload =
      Data("krc1".utf8)
      + Data(
        compressed("[1200,900]<0,400,0>A<400,500,0>B").enumerated().map {
          $0.element ^ key[$0.offset % 16]
        })
    LyricsStub.respond = { request in
      if request.url!.path == "/search" {
        XCTAssertTrue(request.url!.absoluteString.contains("hash=EXACT_HASH"))
        return try self.json(["candidates": [["id": "42", "accesskey": "key"]]])
      }
      return try self.json(["fmt": "krc", "content": payload.base64EncodedString()])
    }
    let document = try await service().lyrics(
      for: track(.kg, info: ["hash": .string("EXACT_HASH")]))
    XCTAssertEqual(document.lines.first?.text, "AB")
    XCTAssertEqual(document.lines.first?.time, 1.2)
  }
  func testMiguUsesProvidedLyricURLsAndTranslation() async throws {
    LyricsStub.respond = { request in
      Data((request.url!.path == "/translation" ? "[00:01]译文" : "[00:01]Original").utf8)
    }
    let document = try await service().lyrics(
      for: track(
        .mg,
        info: [
          "lrcUrl": .string("https://example.test/lyric"),
          "trcUrl": .string("https://example.test/translation"),
        ]))
    XCTAssertEqual(document.lines.first?.text, "Original")
    XCTAssertEqual(document.lines.first?.translation, "译文")
  }
  func testFailuresCanRetryAndPlatformCacheKeysStaySeparate() async throws {
    let service = service()
    LyricsStub.respond = { _ in throw URLError(.notConnectedToInternet) }
    do {
      _ = try await service.lyrics(for: track(.wy))
      XCTFail("Should fail offline")
    } catch {}
    LyricsStub.respond = { request in
      if request.url!.host == "music.163.com" {
        return try self.json(["code": 200, "lrc": ["lyric": "[00:01]NetEase"]])
      }
      return try self.json(["code": 0, "lyric": "[00:01]QQ"])
    }
    let wy = try await service.lyrics(for: track(.wy))
    let qq = try await service.lyrics(for: track(.tx))
    XCTAssertEqual(wy.lines.first?.text, "NetEase")
    XCTAssertEqual(qq.lines.first?.text, "QQ")
  }
}

final class LiveLyricsTests: XCTestCase {
  func testLivePlatformLyrics() async throws {
    guard ProcessInfo.processInfo.environment["MUSIC_LYRICS_NETWORK_TESTS"] == "1" else {
      throw XCTSkip("Set MUSIC_LYRICS_NETWORK_TESTS=1")
    }
    let catalog = MusicCatalog()
    let service = LyricsService(cacheDirectory: nil)
    for platform in MusicPlatform.allCases {
      do {
        let track: Track
        if platform == .tx {
          // Exercise lyrics independently of the intermittently unavailable QQ search API.
          track = Track(
            platform: .tx, songID: "0039MnYb0qxYhV", title: "QQ lyric sample", artist: "")
        } else {
          let tracks = try await catalog.search("Queen", platform: platform).tracks
          track = try XCTUnwrap(tracks.first)
        }
        let document = try await service.lyrics(for: track)
        print(
          "LYRICS_SAMPLE \(platform.rawValue): \(document.lines.count) timed lines, \(document.plainText.count) plain characters"
        )
        XCTAssertFalse(document.isEmpty, platform.rawValue)
      } catch { XCTFail("LYRICS_SAMPLE \(platform.rawValue): \(error.localizedDescription)") }
    }
  }
}
