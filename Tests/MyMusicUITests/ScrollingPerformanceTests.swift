import AppKit
import MusicCore
import QuartzCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class ScrollingPerformanceTests: XCTestCase {
  func testRankedTableScrollFrameBudget() async throws {
    guard ProcessInfo.processInfo.environment["MYMUSIC_SCROLL_BENCHMARK"] == "1" else {
      throw XCTSkip("Opt-in release-mode native scrolling benchmark")
    }
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    let songs = (0..<1000).map {
      Track(
        platform: .wy, songID: String($0), title: "Song \($0)", artist: "Artist", album: "Album",
        duration: 240)
    }
    model.state.queue.entries = songs.map { QueueEntry(track: $0) }
    model.state.queue.currentID = model.state.queue.entries.last?.id
    let root = NSHostingView(
      rootView: TracksView(tracks: songs, ranked: true).environmentObject(model))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 500),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = root
    defer { window.close() }
    func settle() async {
      for _ in 0..<3 {
        await withCheckedContinuation { continuation in
          DispatchQueue.main.async { continuation.resume() }
        }
        root.layoutSubtreeIfNeeded()
      }
    }
    await settle()
    func table(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView { return table }
      return view.subviews.lazy.compactMap { table(in: $0) }.first
    }
    let native = try XCTUnwrap(table(in: root))
    let scroll = try XCTUnwrap(native.enclosingScrollView)
    XCTAssertEqual(native.numberOfRows, songs.count)
    let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
    var milliseconds: [Double] = []
    for frame in 0..<100 {
      let start = CACurrentMediaTime()
      if frame % 30 == 0 {
        model.updatePlaybackTime(position: model.position + 0.5, duration: 240)
      }
      scroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(frame) * 42))
      scroll.reflectScrolledClipView(scroll.contentView)
      let visible = native.rows(in: scroll.contentView.bounds)
      if visible.location != NSNotFound {
        for row in visible.location..<min(native.numberOfRows, NSMaxRange(visible)) {
          _ = native.rowView(atRow: row, makeIfNecessary: true)
        }
      }
      await settle()
      root.cacheDisplay(in: root.bounds, to: bitmap)
      if frame > 9 { milliseconds.append((CACurrentMediaTime() - start) * 1000) }
    }
    let sorted = milliseconds.sorted()
    let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
    let mean = sorted.reduce(0, +) / Double(sorted.count)
    print(
      "SCROLL_BENCHMARK rows=\(songs.count) mean_ms=\(mean) p95_ms=\(p95) max_ms=\(sorted.last!)")
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 3000)
    XCTAssertLessThan(p95, 16.7, "Offscreen render baseline exceeds the 60 Hz budget")
    XCTAssertLessThan(
      sorted.last!, 33.4, "Playback ticks must not stall scrolling for multiple frames")
  }
}
