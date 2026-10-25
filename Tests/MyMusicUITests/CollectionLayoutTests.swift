import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class CollectionLayoutTests: XCTestCase {
  private final class Frames { var views: [Int: NSView] = [:] }
  private struct Probe: NSViewRepresentable {
    let index: Int
    let frames: Frames
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      frames.views[index] = view
      return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
  }
  private func settle(_ root: NSView) async throws {
    for _ in 0..<12 {
      root.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(20))
    }
  }
  private func window(_ root: NSView, width: CGFloat = 768, height: CGFloat = 450) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: width, height: height),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = root
    return window
  }
  func testGridFitsFourCompactCoversAlongsideTheQueue() async throws {
    let frames = Frames()
    let root = NSHostingView(
      rootView: CollectionGrid {
        ForEach(0..<8) { index in
          Color.clear.frame(height: 160).background(Probe(index: index, frames: frames))
        }
      }.frame(width: 768, height: 450, alignment: .top))
    let window = window(root)
    defer { window.close() }
    try await settle(root)
    let first = try XCTUnwrap(frames.views[0])
    let y = first.convert(first.bounds, to: root).minY
    for index in 0..<4 {
      let view = try XCTUnwrap(frames.views[index])
      XCTAssertEqual(view.convert(view.bounds, to: root).minY, y, accuracy: 1)
      XCTAssertGreaterThanOrEqual(view.bounds.width, 155)
      XCTAssertLessThanOrEqual(view.bounds.width, 170)
    }
    let next = try XCTUnwrap(frames.views[4])
    XCTAssertGreaterThan(abs(next.convert(next.bounds, to: root).minY - y), 100)
  }
  func testSingleLineCardDoesNotReserveAnEmptySecondTitleLine() async throws {
    let frames = Frames()
    func card(_ title: String, index: Int) -> some View {
      CollectionCard(
        collection: MusicCollection(
          id: String(index), title: title, subtitle: "Artist", platform: .wy),
        saved: false, lists: [], busy: false, actionsDisabled: false,
        open: {}, perform: { _ in }, cancel: {}
      ).frame(width: 160).background(Probe(index: index, frames: frames))
    }
    let root = NSHostingView(
      rootView: HStack(alignment: .top) {
        card("Short title", index: 0)
        card("A longer playlist title that needs two lines", index: 1)
      }.fixedSize())
    let window = window(root, width: 400)
    defer { window.close() }
    try await settle(root)
    let short = try XCTUnwrap(frames.views[0])
    let long = try XCTUnwrap(frames.views[1])
    XCTAssertGreaterThan(long.bounds.height - short.bounds.height, 10)
    XCTAssertLessThan(long.bounds.height - short.bounds.height, 25)
  }
  func testNewRetainedDetailBindsItsOwnTableAndPagination() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    let songs = (0..<100).map {
      Track(
        platform: .wy, songID: String($0), title: "Song \($0)", artist: "Artist", album: "Album")
    }
    var requests = 0
    func content(second: Bool) -> some View {
      ZStack {
        TracksView(tracks: songs, scrollHeader: AnyView(Color.blue.frame(height: 180)))
          .modifier(RetainedPage(active: !second))
        if second {
          TracksView(
            tracks: songs, ranked: true, loadMore: { requests += 1 },
            scrollHeader: AnyView(Color.red.frame(height: 180))
          )
          .modifier(RetainedPage(active: true))
        }
      }.environmentObject(model)
    }
    let root = NSHostingView(rootView: content(second: false))
    let window = window(root)
    defer { window.close() }
    try await settle(root)
    root.rootView = content(second: true)
    try await settle(root)
    func tables(_ view: NSView) -> [NSTableView] {
      (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
    }
    let all = tables(root)
    XCTAssertEqual(all.count, 2)
    let table = try XCTUnwrap(all.last)
    let scroll = try XCTUnwrap(table.enclosingScrollView)
    XCTAssertFalse(table.usesAlternatingRowBackgroundColors)
    XCTAssertNil(table.headerView)
    XCTAssertGreaterThan(try XCTUnwrap(scroll.contentView as? MusicTableClipView).headerHeight, 220)
    scroll.contentView.scroll(
      to: NSPoint(x: 0, y: table.bounds.height - scroll.contentView.bounds.height))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle(root)
    XCTAssertEqual(requests, 1)
    let origin = scroll.contentView.bounds.origin.y
    let visibleRow = table.row(at: NSPoint(x: 100, y: origin + 80))
    XCTAssertGreaterThanOrEqual(visibleRow, 0)
    table.scrollRowToVisible(visibleRow)
    XCTAssertEqual(
      scroll.contentView.bounds.origin.y, origin, accuracy: 1,
      "Selecting an already visible song must not jump below the former header inset")
    let point = table.convert(NSPoint(x: 100, y: scroll.contentView.bounds.midY), to: root)
    let target = try XCTUnwrap(root.hitTest(point))
    XCTAssertTrue(
      target === table || target.isDescendant(of: table),
      "Scroll boundaries must not intercept native table clicks: \(type(of: target))")
  }
  func testArtworkScrollsAwayWhileColumnsPinAndAppendPreservesPosition() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    let tracks = (0..<1000).map {
      Track(
        platform: .wy, songID: String($0), title: "Song \($0)", artist: "Artist", album: "Album")
    }
    var collapsed = false
    func content(_ songs: [Track]) -> some View {
      TracksView(
        tracks: songs, scrollHeader: AnyView(Color.blue.frame(height: 180)),
        headerCollapsed: { collapsed = $0 }
      ).environmentObject(model)
    }
    let root = NSHostingView(rootView: content(Array(tracks.prefix(100))))
    let window = window(root)
    defer { window.close() }
    try await settle(root)
    func find(_ node: NSView) -> NSTableView? {
      if let table = node as? NSTableView { return table }
      return node.subviews.lazy.compactMap(find).first
    }
    let table = try XCTUnwrap(find(root))
    let scroll = try XCTUnwrap(table.enclosingScrollView)
    XCTAssertGreaterThan(try XCTUnwrap(scroll.contentView as? MusicTableClipView).headerHeight, 220)
    XCTAssertLessThan(scroll.contentView.bounds.minY, -220)
    XCTAssertFalse(collapsed)
    XCTAssertNil(table.headerView)
    let scroller = try XCTUnwrap(scroll.verticalScroller)
    XCTAssertEqual(scroller.frame.height, scroll.contentView.frame.height, accuracy: 2)
    let columns = try XCTUnwrap(
      scroll.contentView.subviews.compactMap { $0 as? NSTableHeaderView }.first)
    XCTAssertTrue(columns.tableView === table)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle(root)
    XCTAssertTrue(collapsed)
    XCTAssertEqual(columns.frame.minY, scroll.contentView.bounds.minY, accuracy: 1)
    let position = scroll.contentView.bounds.minY
    root.rootView = content(tracks)
    try await settle(root)
    XCTAssertEqual(table.numberOfRows, 1000)
    XCTAssertEqual(scroll.contentView.bounds.minY, position, accuracy: 1)
    var count = 0
    table.enumerateAvailableRowViews { _, _ in count += 1 }
    XCTAssertLessThan(count, 50, "A long playlist must continue rendering only visible rows")
    let clip = try XCTUnwrap(scroll.contentView as? MusicTableClipView)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: -clip.headerHeight))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle(root)
    XCTAssertFalse(collapsed)
    XCTAssertLessThan(columns.frame.minY, 0)
  }
}
