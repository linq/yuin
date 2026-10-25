import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class TrackSelectionTests: XCTestCase {
  func testHistorySelectionKeepsRedBackgroundAfterSwiftUIUpdatesCells() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    let tracks = (0..<8).map {
      Track(platform: .wy, songID: "\($0)", title: "Song \($0)", artist: "Artist", album: "Album")
    }
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      let host = NSHostingView(rootView: TrackLibraryView(tracks: tracks).environmentObject(model))
      let window = NSWindow(
        contentRect: NSRect(x: -5000, y: -5000, width: 850, height: 400),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: appearance)
      window.contentView = host
      defer { window.close() }
      func settle() async throws {
        for _ in 0..<12 {
          host.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(20))
        }
      }
      func find(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap(find).first
      }
      try await settle()
      let table = try XCTUnwrap(find(host))
      func pixel(_ index: Int) throws -> NSColor {
        let row = try XCTUnwrap(table.rowView(atRow: index, makeIfNecessary: true))
        let bitmap = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: bitmap)
        return try XCTUnwrap(
          bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
        )
      }
      for indexes: IndexSet in [[1], [2], [0], [0, 2], []] {
        table.selectRowIndexes(indexes, byExtendingSelection: false)
        try await settle()
        for index in 0..<3 {
          let color = try pixel(index)
          if indexes.contains(index) {
            XCTAssertGreaterThan(color.redComponent, color.greenComponent * 2)
            XCTAssertGreaterThan(color.redComponent, color.blueComponent * 2)
          } else {
            XCTAssertLessThan(color.redComponent, color.greenComponent * 1.5 + 0.1)
          }
        }
      }
      table.selectRowIndexes([1], byExtendingSelection: false)
      try await settle()
      host.rootView = TrackLibraryView(
        tracks: [Track(platform: .wy, songID: "new", title: "New history song", artist: "Artist")]
          + tracks
      ).environmentObject(model)
      try await settle()
      XCTAssertEqual(
        table.selectedRowIndexes, [2], "Prepending history must keep the selected song")
      let moved = try pixel(2)
      XCTAssertGreaterThan(moved.redComponent, moved.greenComponent * 2)
      XCTAssertGreaterThan(moved.redComponent, moved.blueComponent * 2)
    }
  }
  private final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { 4 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      NSTextField(labelWithString: "Song \(row)")
    }
  }
  func testSelectionStaysRedInBothAppearancesAndClearsWhenItMoves() throws {
    _ = NSApplication.shared
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      let window = NSWindow(
        contentRect: NSRect(x: -5000, y: -5000, width: 300, height: 200),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: appearance)
      defer { window.close() }
      let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
      let column = NSTableColumn(identifier: .init("song"))
      column.width = 280
      table.addTableColumn(column)
      table.rowHeight = 32
      let rows = Rows()
      table.dataSource = rows
      table.delegate = rows
      let scroll = NSScrollView(frame: table.frame)
      scroll.documentView = table
      window.contentView = scroll
      table.reloadData()
      scroll.layoutSubtreeIfNeeded()
      table.layoutSubtreeIfNeeded()
      for index in 0..<4 { _ = table.rowView(atRow: index, makeIfNecessary: true) }
      func pixel(_ index: Int) throws -> NSColor {
        let row = try XCTUnwrap(table.rowView(atRow: index, makeIfNecessary: true))
        row.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: bitmap)
        return try XCTUnwrap(
          bitmap.colorAt(x: bitmap.pixelsWide - 30, y: bitmap.pixelsHigh / 2)?.usingColorSpace(
            .sRGB))
      }
      for index in [0, 2] {
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.layoutSubtreeIfNeeded()
        TrackTableAppearance.updateSelection(in: table)
        let selected = try pixel(index)
        XCTAssertGreaterThan(selected.redComponent, selected.greenComponent * 2)
        XCTAssertGreaterThan(selected.redComponent, selected.blueComponent * 2)
        if index == 2 {
          let old = try pixel(0)
          XCTAssertLessThan(
            old.redComponent, old.greenComponent * 1.5 + 0.1,
            "A reused row must not retain the old red selection")
        }
      }
      table.deselectAll(nil)
      TrackTableAppearance.updateSelection(in: table)
      let cleared = try pixel(2)
      XCTAssertLessThan(cleared.redComponent, cleared.greenComponent * 1.5 + 0.1)
      withExtendedLifetime(rows) {}
    }
  }
}
