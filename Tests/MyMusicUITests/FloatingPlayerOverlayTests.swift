import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class FloatingPlayerOverlayTests: XCTestCase {
  func testSongsScrollBehindThePlayerAndTheLastSongCanClearIt() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    let tracks = (0..<100).map {
      Track(platform: .wy, songID: "\($0)", title: "Song \($0)", artist: "Artist")
    }
    let host = NSHostingView(
      rootView: TracksView(tracks: tracks).modifier(FloatingPlayerOverlay()).environmentObject(
        model))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 800, height: 450), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() async throws {
      for _ in 0..<12 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    func find(_ node: NSView) -> NSTableView? {
      if let table = node as? NSTableView { return table }
      return node.subviews.lazy.compactMap(find).first
    }
    try await settle()
    let table = try XCTUnwrap(find(host))
    let scroll = try XCTUnwrap(table.enclosingScrollView)
    let clip = scroll.contentView
    XCTAssertGreaterThan(
      clip.frame.height, host.bounds.height - 40,
      "The player must not reserve a separate band below the table")
    var bottom = clip.bounds
    bottom.origin.y = table.bounds.maxY
    clip.scroll(to: clip.constrainBoundsRect(bottom).origin)
    scroll.reflectScrolledClipView(clip)
    try await settle()
    let last = table.convert(table.rect(ofRow: 99), to: host)
    XCTAssertLessThanOrEqual(
      last.maxY, host.bounds.height - FloatingPlayerOverlay.scrollClearance + 2,
      "The last song must scroll fully above the floating player")
  }
}
