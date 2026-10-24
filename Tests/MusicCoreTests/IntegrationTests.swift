import AVFoundation
import XCTest

@testable import MusicCore

@MainActor final class IntegrationTests: XCTestCase {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  private func host() throws -> URL {
    let paths = [".build/debug/MusicSourceHost", ".build/out/Products/Debug/MusicSourceHost"]
    return try XCTUnwrap(
      paths.map { root.appendingPathComponent($0) }.first {
        FileManager.default.isExecutableFile(atPath: $0.path)
      })
  }
  private func server() throws -> (Process, Int) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [root.appendingPathComponent("Tests/Fixtures/server.py").path]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.availableData
    guard
      let port = Int(
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      process.terminate()
      throw MusicError.message("Fixture server did not start")
    }
    return (process, port)
  }
  func testOnlineImportDownloadDuplicateAndOfflinePlayback() async throws {
    let (server, port) = try server()
    defer { if server.isRunning { server.terminate() } }
    let runtime = SourceRuntime()
    defer { runtime.stop() }
    let record = try await SourceImport.online("http://127.0.0.1:\(port)/source.js")
    XCTAssertTrue(record.name.contains("fixture"))
    XCTAssertNotNil(record.origin)
    try await runtime.start(record, executable: host())
    let track = Track(
      platform: .kw, songID: "integration", title: "Generated silence", artist: "Test fixture")
    let url = try await runtime.resolve(track, quality: "128k")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = try await DownloadService.download(
      url, track: track, quality: "128k", directory: directory
    ) { _ in }
    XCTAssertFalse(result.skipped)
    XCTAssertEqual(result.url.pathExtension, "wav")
    let duplicate = try await DownloadService.download(
      url, track: track, quality: "128k", directory: directory
    ) { _ in }
    XCTAssertTrue(duplicate.skipped)
    XCTAssertEqual(duplicate.url, result.url)
    let original = try Data(contentsOf: result.url)
    XCTAssertGreaterThan(original.count, 100000)
    server.terminate()
    runtime.stop()
    let player = AVPlayer(url: result.url)
    player.isMuted = true
    player.play()
    defer { player.pause() }
    for _ in 0..<30 {
      if player.currentTime().seconds > 0.1 { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertGreaterThan(
      player.currentTime().seconds, 0.1,
      "AVPlayer must advance from the downloaded local file without server/source")
    XCTAssertEqual(try Data(contentsOf: result.url), original)
  }
  func testHTTPRequestFormAndCallbackBuffers() async throws {
    let (server, port) = try server()
    defer { server.terminate() }
    let script = """
      lx.on('request',()=>new Promise((resolve,reject)=>{
        lx.request('http://127.0.0.1:\(port)/echo',{method:'POST',form:{name:'A+B 你好'}},(error,response,body)=>{
          if(error)return reject(error);
          if(response.statusCode!==200||response.bytes<1||!body.body.includes('A%2BB'))return reject(new Error('HTTP bridge mismatch'));
          if(JSON.parse(lx.utils.buffer.bufToString(response.raw)).body!==body.body)return reject(new Error('raw bytes mismatch'));
          resolve('http://127.0.0.1:\(port)/audio.wav');
        });
      }));
      lx.send('inited',{sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});
      """
    let runtime = SourceRuntime()
    defer { runtime.stop() }
    try await runtime.start(SourceRecord(script: script), executable: host())
    _ = try await runtime.resolve(
      Track(platform: .kw, songID: "1", title: "T", artist: "A"), quality: "128k")
  }
  func testAESAndRSAMatchOpenSSLVectors() async throws {
    let vectors = try Data(
      contentsOf: root.appendingPathComponent("Tests/Fixtures/crypto-vectors.json"))
    let json = String(decoding: vectors, as: UTF8.self)
    let script = """
      const vectors = \(json);
      const {buffer,crypto} = lx.utils;
      const aes = crypto.aesEncrypt(buffer.from(vectors.aes.plain),'aes-128-cbc',buffer.from(vectors.aes.key),buffer.from(vectors.aes.iv));
      if(buffer.bufToString(aes,'hex')!==vectors.aes.hex)throw Error('AES mismatch');
      const rsa = crypto.rsaEncrypt(buffer.from(vectors.rsa.plain),vectors.rsa.publicKey);
      if(buffer.bufToString(rsa,'hex')!==vectors.rsa.hex)throw Error('RSA mismatch');
      if(crypto.randomBytes(0).length!==0)throw Error('zero length random bytes');
      lx.on('request',async()=> 'https://example.invalid/test.mp3');
      lx.send('inited',{sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});
      """
    let runtime = SourceRuntime()
    defer { runtime.stop() }
    try await runtime.start(SourceRecord(script: script), executable: host())
  }

  func testInfiniteScriptIsTerminatedWithoutHangingCaller() async throws {
    let runtime = SourceRuntime()
    defer { runtime.stop() }
    let start = Date()
    do {
      try await runtime.start(
        SourceRecord(script: "while(true) {}"), executable: host(), startupTimeout: 0.3)
      XCTFail("Must time out")
    } catch { XCTAssertTrue(error.localizedDescription == L10n.text("音乐源响应超时，已停止脚本；请重新启用或切换源")) }
    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
  }
  func testDownloadCancellationLeavesNoFinalFile() async throws {
    let (server, port) = try server()
    defer { server.terminate() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let task = Task {
      try await DownloadService.download(
        URL(string: "http://127.0.0.1:\(port)/slow")!,
        track: Track(platform: .kw, songID: "1", title: "T", artist: "A"), quality: "128k",
        directory: directory
      ) { _ in }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled download must fail")
    } catch {}
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
  }

  func testDownloadRejectsSourceQualityDowngrade() async throws {
    let (server, port) = try server()
    defer { server.terminate() }
    for (filename, quality) in [
      ("silence-320.mp3", "flac"), ("silence-320.mp3", "flac24bit"),
      ("silence-16.flac", "flac24bit"), ("silence-128.mp3", "320k"),
    ] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      do {
        _ = try await DownloadService.download(
          URL(string: "http://127.0.0.1:\(port)/\(filename)")!,
          track: Track(platform: .kw, songID: "quality", title: "Silence", artist: "Fixture"),
          quality: quality, directory: directory
        ) { _ in }
        XCTFail("Must reject \(filename) when requesting \(quality)")
      } catch {
        XCTAssertTrue(
          error.localizedDescription.contains(L10n.text("音质不符")), error.localizedDescription)
      }
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }
  }

  func testDownloadAcceptsMatchingQualityAndRechecksExistingFiles() async throws {
    let (server, port) = try server()
    defer { server.terminate() }
    let track = Track(platform: .kw, songID: "quality", title: "Silence", artist: "Fixture")
    for (filename, quality) in [
      ("silence-128.mp3", "128k"), ("silence-320.mp3", "320k"), ("silence-16.flac", "flac"),
      ("silence-24.flac", "flac24bit"),
    ] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let url = URL(string: "http://127.0.0.1:\(port)/\(filename)")!
      let result = try await DownloadService.download(
        url, track: track, quality: quality, directory: directory
      ) { _ in }
      XCTAssertFalse(result.skipped)
      let duplicate = try await DownloadService.download(
        url, track: track, quality: quality, directory: directory
      ) { _ in }
      XCTAssertTrue(duplicate.skipped)
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let invalidExisting = directory.appendingPathComponent(
      DownloadFiles.filename(track: track, quality: "flac", extension: "mp3"))
    let original = try Data(
      contentsOf: root.appendingPathComponent("Tests/Fixtures/silence-320.mp3"))
    try original.write(to: invalidExisting)
    do {
      _ = try await DownloadService.download(
        URL(string: "http://127.0.0.1:\(port)/silence-16.flac")!, track: track, quality: "flac",
        directory: directory
      ) { _ in }
      XCTFail("Old mislabeled downloads must not be reported as successful duplicates")
    } catch { XCTAssertTrue(error.localizedDescription.contains(L10n.text("音质不符"))) }
    XCTAssertEqual(
      try Data(contentsOf: invalidExisting), original, "Do not delete or overwrite existing files")
  }
}
