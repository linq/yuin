import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class TrackListDensityTests: XCTestCase {
  private func settle(_ view: NSView) async throws {
    for _ in 0..<16 {
      view.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(15))
    }
  }
  private func table(in view: NSView) -> NSTableView? {
    if let table = view as? NSTableView { return table }
    return view.subviews.lazy.compactMap { self.table(in: $0) }.first
  }
  func testDensityChangesActualRowsAndKeepsSelectionAndVisibleSong() async throws {
    _ = NSApplication.shared
    let suite = UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    let tracks = (0..<1000).map {
      Track(platform: .wy, songID: "\($0)", title: "Song \($0)", artist: "Artist", album: "Album")
    }
    func content() -> some View {
      TracksView(tracks: tracks).environmentObject(model).defaultAppStorage(preferences)
    }
    let host = NSHostingView(rootView: content())
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 850, height: 450),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    try await settle(host)
    let original = try XCTUnwrap(table(in: host))
    let scroll = try XCTUnwrap(original.enclosingScrollView)
    XCTAssertEqual(original.rect(ofRow: 0).height, 32, accuracy: 1)
    original.selectRowIndexes([33], byExtendingSelection: false)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: original.rect(ofRow: 30).minY + 4))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle(host)
    let row = original.row(at: NSPoint(x: 1, y: scroll.contentView.bounds.minY))
    TrackListDensity.prepareForChange()
    preferences.set(TrackListDensity.compact.rawValue, forKey: TrackListDensity.preferenceKey)
    try await settle(host)
    XCTAssertTrue(table(in: host) === original)
    XCTAssertEqual(original.rect(ofRow: 31).height, 26, accuracy: 1)
    XCTAssertEqual(original.selectedRowIndexes, [33])
    XCTAssertEqual(original.row(at: NSPoint(x: 1, y: scroll.contentView.bounds.minY)), row)
    var rendered = 0
    original.enumerateAvailableRowViews { _, _ in rendered += 1 }
    XCTAssertLessThan(rendered, 60)
    // A fresh view reads the same saved preference rather than resetting density.
    let second = NSHostingView(rootView: content())
    window.contentView = second
    try await settle(second)
    XCTAssertEqual(try XCTUnwrap(table(in: second)).rect(ofRow: 0).height, 26, accuracy: 1)
  }
}
