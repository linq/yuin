import AppKit
import XCTest

@testable import MyMusic

@MainActor final class ScrollPaginationTests: XCTestCase {
  @MainActor private final class Rows: NSObject, NSTableViewDataSource {
    var count = 100
    func numberOfRows(in tableView: NSTableView) -> Int { count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int)
      -> Any?
    {
      "Song \(row)"
    }
  }
  @MainActor private final class Fixture {
    let rows = Rows()
    let table = NSTableView()
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let anchor = ScrollPositionMemory.AnchorView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let window: NSWindow
    init() {
      _ = NSApplication.shared
      window = NSWindow(
        contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let container = NSView(frame: scroll.frame)
      window.contentView = container
      table.headerView = nil
      table.rowHeight = 28
      table.intercellSpacing = .zero
      table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("song")))
      table.dataSource = rows
      scroll.documentView = table
      scroll.hasVerticalScroller = true
      container.addSubview(scroll)
      container.addSubview(anchor)
      anchor.requiresTable = true
      table.reloadData()
      container.layoutSubtreeIfNeeded()
    }
    func move(to y: CGFloat) {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
      scroll.reflectScrolledClipView(scroll.contentView)
    }
    var bottom: CGFloat { table.bounds.height - scroll.contentView.bounds.height }
  }
  private func settle() async {
    for _ in 0..<5 {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
  }
  func testWrappedNativeTableAndReplacementScrollerUseSharedAppearance() async {
    let fixture = Fixture()
    defer { fixture.window.close() }
    let wrapper = NSView(frame: fixture.table.frame)
    fixture.scroll.documentView = wrapper
    wrapper.addSubview(fixture.table)
    await settle()
    XCTAssertTrue(fixture.scroll.verticalScroller is MusicScroller)
    let original = NSScroller()
    fixture.scroll.verticalScroller = original
    fixture.anchor.refreshAppearance()
    await settle()
    XCTAssertTrue(fixture.scroll.verticalScroller is MusicScroller)
  }

  func testGridAppendPreservesPositionAndRequestsOnlyOnePage() async {
    final class Document: NSView { override var isFlipped: Bool { true } }
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    let window = NSWindow(
      contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let container = NSView(frame: frame)
    window.contentView = container
    let scroll = NSScrollView(frame: frame)
    let document = Document(frame: NSRect(x: 0, y: 0, width: 400, height: 2000))
    scroll.documentView = document
    scroll.hasVerticalScroller = true
    let anchor = ScrollPositionMemory.AnchorView(frame: frame)
    container.addSubview(scroll)
    container.addSubview(anchor)
    var requests = 0
    anchor.updateContent(rowIDs: (0..<18).map(String.init), count: 18, loadMore: { requests += 1 })
    await settle()
    XCTAssertEqual(requests, 0)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 1800))
    scroll.reflectScrolledClipView(scroll.contentView)
    await settle()
    XCTAssertEqual(requests, 1)
    let before = scroll.contentView.bounds.origin
    anchor.updateContent(rowIDs: (0..<36).map(String.init), count: 36, loadMore: { requests += 1 })
    document.setFrameSize(NSSize(width: 400, height: 4000))
    await settle()
    XCTAssertEqual(scroll.contentView.bounds.origin.y, before.y, accuracy: 0.5)
    XCTAssertEqual(requests, 1)
    anchor.setActive(false)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 3800))
    await settle()
    XCTAssertEqual(requests, 1)
  }
  func testBottomRequestsOnePageAndAppendPreservesVisiblePosition() async {
    let fixture = Fixture()
    defer { fixture.window.close() }
    var requests = 0
    fixture.anchor.updateContent(
      rowIDs: (0..<100).map(String.init), count: 100, loadMore: { requests += 1 })
    await settle()
    XCTAssertEqual(requests, 0, "Initial rendering must not fetch all pages")
    fixture.move(to: fixture.bottom - 30)
    await settle()
    XCTAssertEqual(requests, 1)
    fixture.move(to: fixture.bottom - 10)
    await settle()
    XCTAssertEqual(requests, 1, "Repeated bounds notifications must not duplicate a page request")
    let before = fixture.scroll.contentView.bounds.origin.y
    fixture.anchor.updateContent(
      rowIDs: (0..<200).map(String.init), count: 200, loadMore: { requests += 1 })
    fixture.rows.count = 200
    fixture.table.reloadData()
    await settle()
    XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, before, accuracy: 0.5)
    XCTAssertEqual(requests, 1)
    fixture.anchor.updateContent(rowIDs: (0..<200).map(String.init), count: 200, loadMore: nil)
    fixture.move(to: fixture.bottom - 20)
    await settle()
    XCTAssertEqual(
      requests, 1, "Busy, exhausted or failed pagination must not request another page")
    fixture.anchor.updateContent(
      rowIDs: (0..<200).map(String.init), count: 200, loadMore: { requests += 1 })
    fixture.move(to: fixture.bottom - 120)
    fixture.move(to: fixture.bottom - 20)
    await settle()
    XCTAssertEqual(requests, 2)
    let beforeHiding = fixture.scroll.contentView.bounds.origin.y
    fixture.anchor.setActive(false)
    fixture.anchor.updateContent(
      rowIDs: (0..<300).map(String.init), count: 300, loadMore: { requests += 1 })
    fixture.rows.count = 300
    fixture.table.reloadData()
    fixture.move(to: fixture.bottom)
    await settle()
    XCTAssertEqual(requests, 2, "Hidden pages must not fetch")
    fixture.anchor.setActive(true)
    await settle()
    XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, beforeHiding, accuracy: 0.5)
  }
  func testSortedAppendKeepsVisibleSongAndBusyOrFailureDoesNotFetch() async {
    let fixture = Fixture()
    defer { fixture.window.close() }
    fixture.anchor.updateContent(rowIDs: (100..<200).map(String.init), count: 100, loadMore: nil)
    await settle()
    fixture.move(to: 700)
    await settle()
    fixture.anchor.updateContent(rowIDs: (0..<200).map(String.init), count: 200, loadMore: nil)
    fixture.rows.count = 200
    fixture.table.reloadData()
    await settle()
    XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, 3500, accuracy: 0.5)
    fixture.move(to: fixture.bottom)
    await settle()
    XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, fixture.bottom, accuracy: 0.5)
  }
}
