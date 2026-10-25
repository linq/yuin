import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class NavigationInteractionTests: XCTestCase {
  func testHistoryTraversesCatalogDetailsAndSidebarAndBranchesAfterBack() {
    var history = BrowserNavigationHistory()
    let first = MusicLocation(
      section: "playlists", collection: MusicCollection(id: "1", title: "First", platform: .wy))
    let second = MusicLocation(
      section: "charts",
      collection: MusicCollection(id: "1", title: "Chart", platform: .kw, isChart: true))
    history.visit(first)
    history.visit(MusicLocation(section: "history"))
    history.visit(second)
    history.back()
    XCTAssertEqual(history.current.section, "history")
    history.back()
    XCTAssertEqual(history.current, first)
    history.forward()
    XCTAssertEqual(history.current.section, "history")
    history.visit(MusicLocation(section: "downloads"))
    XCTAssertFalse(history.canGoForward)
    XCTAssertTrue(history.visited.contains(first))
    XCTAssertFalse(history.visited.contains(second))
    let count = history.locations.count
    history.visit(history.current)
    XCTAssertEqual(history.locations.count, count)
  }
  func testDeletingAListRemovesItsStaleHistoryWithoutBreakingBackOrForward() {
    var history = BrowserNavigationHistory()
    history.visit(MusicLocation(section: "list:deleted"))
    history.visit(MusicLocation(section: "history"))
    history.back()
    history.removeMissingLists(valid: ["history"])
    XCTAssertFalse(history.locations.contains { $0.section == "list:deleted" })
    history.back()
    XCTAssertEqual(history.current.section, "playlists")
    history.forward()
    XCTAssertEqual(history.current.section, "history")
  }
  func testGridArrowKeysFollowTheAdaptiveColumnCountAndClampEdges() {
    XCTAssertEqual(
      CollectionKeyboardNavigation.destination(
        current: nil, count: 20, width: 768, direction: .down), 0)
    XCTAssertEqual(
      CollectionKeyboardNavigation.destination(current: 2, count: 20, width: 768, direction: .down),
      6)
    XCTAssertEqual(
      CollectionKeyboardNavigation.destination(current: 6, count: 20, width: 768, direction: .up), 2
    )
    XCTAssertEqual(
      CollectionKeyboardNavigation.destination(current: 2, count: 20, width: 530, direction: .down),
      4)
    XCTAssertEqual(
      CollectionKeyboardNavigation.destination(current: 0, count: 20, width: 530, direction: .left),
      0)
    XCTAssertEqual(
      CollectionKeyboardNavigation.destination(
        current: 19, count: 20, width: 768, direction: .right), 19)
  }

  private final class Driver: ObservableObject {
    @Published var history = BrowserNavigationHistory()
  }
  private struct Fixture: View {
    @ObservedObject var driver: Driver
    let tracks: [Track]
    var body: some View {
      ZStack {
        ForEach(driver.history.visited) { location in
          TracksView(tracks: tracks)
            .modifier(RetainedPage(active: driver.history.current == location))
        }
      }
    }
  }
  func testBackRestoresTheSameNativeTableSelectionScrollAndKeyboardFocus() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    let driver = Driver()
    let tracks = (0..<100).map {
      Track(platform: .wy, songID: "\($0)", title: "Song \($0)", artist: "Artist")
    }
    let host = NSHostingView(
      rootView: Fixture(driver: driver, tracks: tracks).environmentObject(model))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 800, height: 450), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func tables(_ node: NSView) -> [NSTableView] {
      if let table = node as? NSTableView { return [table] }
      return node.subviews.flatMap(tables)
    }
    func settle() async throws {
      for _ in 0..<16 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    try await settle()
    let first = try XCTUnwrap(tables(host).first)
    let scroll = try XCTUnwrap(first.enclosingScrollView)
    first.selectRowIndexes([32], byExtendingSelection: false)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: first.rect(ofRow: 30).minY + 3))
    scroll.reflectScrolledClipView(scroll.contentView)
    window.makeFirstResponder(first)
    try await settle()
    let origin = scroll.contentView.bounds.origin.y
    driver.history.visit(MusicLocation(section: "history"))
    try await settle()
    let second = try XCTUnwrap(tables(host).first { $0 !== first })
    window.makeFirstResponder(second)
    second.selectRowIndexes([2], byExtendingSelection: false)
    try await settle()
    driver.history.back()
    try await settle()
    XCTAssertTrue(tables(host).contains { $0 === first })
    XCTAssertEqual(first.selectedRowIndexes, IndexSet(integer: 32))
    XCTAssertEqual(scroll.contentView.bounds.origin.y, origin, accuracy: 1)
    XCTAssertTrue(window.firstResponder === first)
    driver.history.forward()
    try await settle()
    XCTAssertTrue(window.firstResponder === second)
    XCTAssertEqual(second.selectedRowIndexes, IndexSet(integer: 2))
  }
}
