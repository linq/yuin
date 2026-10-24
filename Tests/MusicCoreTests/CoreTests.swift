import XCTest

@testable import MusicCore

final class CoreTests: XCTestCase {
  func song(_ id: String = "1", platform: MusicPlatform = .kw) -> Track {
    Track(platform: platform, songID: id, title: "Song \(id)", artist: "Artist")
  }
  func testQueueAllowsDuplicatesWithoutAmbiguousSelection() {
    var q = PlaybackQueue()
    q.replace([song(), song()], start: 0)
    XCTAssertNotEqual(q.entries[0].id, q.entries[1].id)
    q.append(song("next"), next: true)
    XCTAssertEqual(q.entries.map(\.track.songID), ["1", "next", "1"])
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.current?.songID, "next")
    q.remove(q.currentID!)
    XCTAssertEqual(q.current?.songID, "1")
    XCTAssertFalse(q.advance())
  }
  func testBatchQueueInsertionKeepsOrderDuplicatesAndCurrentPlayback() throws {
    var q = PlaybackQueue()
    q.replace([song("past"), song("current"), song("tail")], start: 1)
    q.position = 42
    let current = q.currentID
    q.append(contentsOf: [song("a"), song("a"), song("b")], next: true)
    XCTAssertEqual(q.entries.map(\.track.songID), ["past", "current", "a", "a", "b", "tail"])
    XCTAssertEqual(Set(q.entries.map(\.id)).count, 6)
    XCTAssertEqual(q.currentID, current)
    XCTAssertEqual(q.position, 42)
    XCTAssertEqual(q.nextEntryID, q.entries[2].id)
    q.append(contentsOf: [song("c"), song("d")], next: false)
    XCTAssertEqual(q.upcoming.map(\.track.songID), ["a", "a", "b", "tail", "c", "d"])
    q = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(q))
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.current?.songID, "a")
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.current?.songID, "a")
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.current?.songID, "b")
  }
  func testBatchQueueOnEmptyQueueStartsAtFirstWithoutRepeatingIt() {
    for next in [true, false] {
      var q = PlaybackQueue()
      q.append(contentsOf: [song("a"), song("b"), song("c")], next: next)
      XCTAssertEqual(q.entries.map(\.track.songID), ["a", "b", "c"])
      XCTAssertEqual(q.current?.songID, "a")
      XCTAssertNil(q.nextEntryID)
      let before = q
      q.append(contentsOf: [], next: next)
      XCTAssertEqual(q, before)
      XCTAssertTrue(q.advance())
      XCTAssertEqual(q.current?.songID, "b")
    }
  }
  func testBatchPlayNextOverridesPriorityInShuffle() {
    var q = PlaybackQueue()
    q.replace([song("current"), song("tail")], start: 0)
    q.mode = .shuffle
    q.append(song("old next"), next: true)
    q.append(contentsOf: [song("new first"), song("new second")], next: true)
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.current?.songID, "new first")
  }
  func testQueueEditsPreserveCurrentIdentityAndPosition() {
    var q = PlaybackQueue()
    q.replace([song("past"), song("current"), song("a"), song("b"), song("c")], start: 1)
    q.position = 42
    let current = q.currentID
    q.moveUpcoming(from: IndexSet([0, 2]), to: 3)
    XCTAssertEqual(q.upcoming.map(\.track.songID), ["b", "a", "c"])
    q.playNext(q.upcoming.last!.id)
    XCTAssertEqual(q.upcoming.map(\.track.songID), ["c", "b", "a"])
    XCTAssertEqual(q.currentID, current)
    XCTAssertEqual(q.position, 42)
    q.clearUpcoming()
    XCTAssertEqual(q.entries.map(\.track.songID), ["current"])
    XCTAssertEqual(q.currentID, current)
    XCTAssertEqual(q.position, 42)
  }
  func testQueueReorderRejectsStaleOffsetsAndHandlesNoCurrent() {
    var q = PlaybackQueue()
    q.replace([song("a"), song("b")], start: -1)
    q.moveUpcoming(from: IndexSet(integer: 1), to: 0)
    XCTAssertEqual(q.entries.map(\.track.songID), ["b", "a"])
    let before = q
    q.moveUpcoming(from: IndexSet(integer: 2), to: 0)
    XCTAssertEqual(q, before)
    q.clearUpcoming()
    XCTAssertTrue(q.entries.isEmpty)
  }
  func testTrackFilteringSortingPreservesIdentityAndOriginalRankOrder() {
    let a = Track(
      platform: .wy, songID: "a", title: "Song 10", artist: "Queen", album: "Live", duration: 40)
    let b = Track(platform: .wy, songID: "b", title: "Song 2", artist: "Queen", duration: 30)
    let c = Track(
      platform: .wy, songID: "c", title: "Other", artist: "Else", album: "LIVE", duration: 20)
    XCTAssertEqual(
      TrackPresentation.tracks([a, b, c], matching: " queen ", order: .original), [a, b])
    XCTAssertEqual(
      TrackPresentation.tracks([a, b, c], matching: "live", order: .original), [a, c])
    XCTAssertEqual(TrackPresentation.tracks([a, b, c], matching: "queen", order: .title), [b, a])
    XCTAssertEqual(TrackPresentation.tracks([a, b, c], matching: "", order: .duration), [c, b, a])
    XCTAssertEqual(TrackPresentation.tracks([a, b, c], matching: "missing", order: .original), [])
  }
  func testExplicitPlayNextIsHonoredInShuffleAndSurvivesSave() throws {
    var q = PlaybackQueue()
    q.replace([song("a"), song("current"), song("b")], start: 1)
    q.mode = .shuffle
    XCTAssertEqual(q.upcoming.count, 2)
    q.moveUpcoming(from: IndexSet(integer: 1), to: 0)
    XCTAssertEqual(q.current?.songID, "current")
    let next = q.upcoming[0]
    q.playNext(next.id)
    q = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(q))
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.currentID, next.id)
    XCTAssertNil(q.nextEntryID)
  }
  func testQueueDragSupersedesPendingPriorityAndEmptyNextDoesNotRepeat() {
    var q = PlaybackQueue()
    q.append(song("only"), next: true)
    XCTAssertFalse(q.advance())
    q.append(song("a"), next: true)
    q.append(song("b"), next: false)
    q.moveUpcoming(from: IndexSet(integer: 1), to: 0)
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.current?.songID, "b")
  }
  func testRepeatOnlyRepeatsOnAutomaticAdvance() {
    var q = PlaybackQueue()
    q.replace([song("a"), song("b")], start: 0)
    q.mode = .repeatOne
    XCTAssertTrue(q.advance(automatic: true))
    XCTAssertEqual(q.current?.songID, "a")
    XCTAssertTrue(q.advance())
    XCTAssertEqual(q.current?.songID, "b")
  }
  func testPlaylistDeduplicatesByPlatformAndSong() {
    let list = LocalPlaylist(name: "Test", tracks: [song(), song(), song(platform: .wy)])
    XCTAssertEqual(list.tracks.count, 2)
  }
  func testBackupRoundTripAndInterruptedDownloadRecovery() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("state.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = LibraryStore(url: url)
    var state = LibraryState()
    state.queue.replace([song()], start: 0)
    state.queue.position = 42
    var job = DownloadJob(track: song(), quality: "320k", directory: "/tmp")
    job.status = .downloading
    state.downloads = [job]
    state.sources = [try SourceRecord(script: "/** @name Test */\nvoid 0")]
    state.activeSourceID = state.sources[0].id
    try store.save(state)
    let loaded = try store.load()
    XCTAssertEqual(loaded.queue, state.queue)
    XCTAssertEqual(loaded.sources, state.sources)
    XCTAssertEqual(loaded.downloads[0].status, .failed)
    XCTAssertEqual(loaded.activeSourceID, state.activeSourceID)
  }
  func testRejectsCorruptAndUnknownSchemaWithoutOverwriting() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let bad = Data("not json".utf8)
    try bad.write(to: url)
    XCTAssertThrowsError(try LibraryStore(url: url).load())
    XCTAssertEqual(try Data(contentsOf: url), bad)
    var state = LibraryState()
    state.schema = 99
    XCTAssertThrowsError(try LibraryStore().decode(JSONEncoder().encode(state)))
    state.schema = 1
    state.playlists.append(state.playlists[0])
    XCTAssertThrowsError(try LibraryStore().decode(JSONEncoder().encode(state)))
  }
  func testPlatformPreferencePersistsAndOldLibrariesStillLoad() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(url: directory.appendingPathComponent("library.json"))
    var state = LibraryState()
    state.selectedPlatform = .tx
    try store.save(state)
    XCTAssertEqual(try store.load().selectedPlatform, .tx)
    var legacy = try XCTUnwrap(
      JSONSerialization.jsonObject(with: store.encoded(state)) as? [String: Any])
    legacy.removeValue(forKey: "selectedPlatform")
    let restored = try store.decode(JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(restored.selectedPlatform)
    XCTAssertEqual(restored.playlists, state.playlists)
  }
  func testMetadataRestrictedToHeader() throws {
    let record = try SourceRecord(
      script: "/**\n * @name Real\n * @version 1.0\n */\nconst fake='@name Not metadata';")
    XCTAssertEqual(record.name, "Real")
    XCTAssertEqual(record.version, "1.0")
    XCTAssertThrowsError(try SourceRecord(script: " "))
  }
  func testKwJSON5AndLXMetadata() throws {
    let d = try MusicCatalog.decodeObject(
      Data(
        "{'MUSICRID':'MUSIC_123','SONGNAME':'A &amp; B','ARTIST':'X','ALBUMID':'42','DURATION':'123','N_MINFO':'level:h,bitrate:320,format:mp3,size:5Mb'}"
          .utf8))
    let track = try XCTUnwrap(MusicCatalog.track(d, platform: .kw))
    XCTAssertEqual(track.songID, "123")
    XCTAssertEqual(track.title, "A & B")
    XCTAssertEqual(track.lxInfo["interval"], .string("2:03"))
    XCTAssertEqual(track.lxInfo["albumId"], .string("42"))
    XCTAssertNotNil(track.lxInfo["_types"])
  }
  func testKugouCarriesQualityHashes() throws {
    let track = try XCTUnwrap(
      MusicCatalog.track(
        [
          "Audioid": 123, "OriSongName": "A", "SingerName": "B", "FileHash": "LOW",
          "HQFileHash": "HIGH", "MixSongID": 567,
        ], platform: .kg))
    XCTAssertEqual(track.sourceInfo["hash"], .string("LOW"))
    XCTAssertEqual(
      track.sourceInfo["_types"],
      .object([
        "128k": .object(["hash": .string("LOW")]), "320k": .object(["hash": .string("HIGH")]),
      ]))
  }
  func testDownloadRejectsHTMLAndUsesSafeUniqueNames() throws {
    XCTAssertThrowsError(try DownloadService.audioExtension(Data("<html>error</html>".utf8)))
    XCTAssertEqual(try DownloadService.audioExtension(Data("RIFF1234WAVE".utf8)), "wav")
    let a = Track(platform: .kw, songID: "../1", title: "../../A/B", artist: "C:D")
    let name = DownloadFiles.filename(track: a, quality: "320k", extension: "mp3")
    XCTAssertFalse(name.contains("/"))
    XCTAssertFalse(name.contains(":"))
    XCTAssertNotEqual(
      DownloadFiles.filename(track: song(platform: .wy), quality: "320k", extension: "mp3"),
      DownloadFiles.filename(track: song(), quality: "320k", extension: "mp3"))
  }
}

@MainActor final class SourceRuntimeTests: XCTestCase {
  var host: URL {
    if let path = ProcessInfo.processInfo.environment["MUSIC_SOURCE_HOST"] {
      return URL(fileURLWithPath: path)
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let candidates = [".build/debug/MusicSourceHost", ".build/out/Products/Debug/MusicSourceHost"]
    return candidates.map { root.appendingPathComponent($0) }.first {
      FileManager.default.isExecutableFile(atPath: $0.path)
    }!
  }
  func testSourceInitializationCryptoAndResolve() async throws {
    let script = """
      /** @name Protocol fixture */
      const {crypto,buffer,zlib}=lx.utils;
      if (lx.version!=='2.0.0'||lx.env!=='desktop') throw Error('wrong environment');
      if (crypto.md5('abc')!=='900150983cd24fb0d6963f7d28e17f72') throw Error('md5');
      if (buffer.bufToString(buffer.from('你好'),'base64')!=='5L2g5aW9') throw Error('buffer utf8');
      if (crypto.randomBytes(16).length!==16) throw Error('random bytes');
      lx.on(lx.EVENT_NAMES.request,async ({source,action,info})=>{
        if(info.musicInfo.songmid!=='123'||source!=='kw'||action!=='musicUrl')throw Error('wrong request mapping');
        const compressed=await zlib.deflate(buffer.from('music'));
        if(buffer.bufToString(await zlib.inflate(compressed))!=='music')throw Error('zlib');
        return 'https://example.invalid/test.mp3';
      });
      setTimeout(()=>lx.send(lx.EVENT_NAMES.inited,{sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k','320k','invalid']}}}),10);
      """
    let runtime = SourceRuntime()
    defer { runtime.stop() }
    try await runtime.start(SourceRecord(script: script), executable: host)
    XCTAssertEqual(runtime.capabilities["kw"]?.qualitys, ["128k", "320k"])
    let url = try await runtime.resolve(
      Track(platform: .kw, songID: "123", title: "T", artist: "A"), quality: "320k")
    XCTAssertEqual(url.absoluteString, "https://example.invalid/test.mp3")
    do {
      _ = try await runtime.resolve(
        Track(platform: .wy, songID: "1", title: "T", artist: "A"), quality: "320k")
      XCTFail("Unsupported platform must fail")
    } catch {}
  }
  func testInvalidSourceFailsWithoutAffectingExistingSource() async throws {
    let good = SourceRuntime()
    let bad = SourceRuntime()
    defer {
      good.stop()
      bad.stop()
    }
    try await good.start(
      SourceRecord(
        script:
          "lx.on('request',async()=> 'https://example.invalid/a.mp3');lx.send('inited',{sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});"
      ), executable: host)
    do {
      try await bad.start(
        SourceRecord(script: "throw new Error('broken source');"), executable: host)
      XCTFail("Must reject initialization")
    } catch { XCTAssertTrue(error.localizedDescription.contains("broken source")) }
    let url = try await good.resolve(
      Track(platform: .kw, songID: "1", title: "T", artist: "A"), quality: "128k")
    XCTAssertEqual(url.host, "example.invalid")
  }
}

final class LiveCatalogTests: XCTestCase {
  func testLiveCatalogCoverage() async throws {
    guard ProcessInfo.processInfo.environment["MUSIC_NETWORK_TESTS"] == "1" else {
      throw XCTSkip("Set MUSIC_NETWORK_TESTS=1 to probe live platform interfaces")
    }
    let catalog = MusicCatalog()
    var working = 0
    for platform in MusicPlatform.allCases {
      do {
        let result = try await catalog.search("晴天", platform: platform)
        print("LIVE \(platform.rawValue) search: \(result.tracks.count)/\(result.total)")
        XCTAssertFalse(result.tracks.isEmpty)
      } catch {
        print("LIVE \(platform.rawValue) search unavailable: \(error.localizedDescription)")
      }
      for charts in [false, true] {
        do {
          let lists = try await catalog.collections(platform: platform, charts: charts)
          guard let first = lists.first else {
            print("LIVE \(platform.rawValue) \(charts ? "charts" : "playlists") empty")
            continue
          }
          let tracks = try await catalog.tracks(in: first)
          print(
            "LIVE \(platform.rawValue) \(charts ? "charts" : "playlists"): \(lists.count) collections, first \(tracks.tracks.count)/\(tracks.total) songs"
          )
          if !tracks.tracks.isEmpty {
            let full = try await catalog.allTracks(in: first)
            XCTAssertFalse(full.isEmpty)
            print(
              "LIVE \(platform.rawValue) \(charts ? "charts" : "playlists") full copy: \(full.count) songs"
            )
            working += 1
          }
        } catch {
          print(
            "LIVE \(platform.rawValue) \(charts ? "charts" : "playlists") unavailable: \(error.localizedDescription)"
          )
        }
      }
    }
    XCTAssertGreaterThanOrEqual(working, 2, "Need live playlist and chart coverage")
  }
}
