import AppKit
import XCTest

@testable import MyMusic

@MainActor final class TrackSelectionTests: XCTestCase {
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
