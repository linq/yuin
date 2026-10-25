import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class QueuePresentationTests: XCTestCase {
  private final class LayoutProbe {
    weak var view: NSView?
  }
  private struct Probe: NSViewRepresentable {
    let probe: LayoutProbe
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      probe.view = view
      return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
  }
  private struct InspectorFixture: View {
    @ObservedObject var model: AppModel
    let probe: LayoutProbe
    var body: some View {
      NavigationSplitView {
        Color.gray.navigationSplitViewColumnWidth(200)
      } detail: {
        Color.red.background(Probe(probe: probe))
      }
      .inspector(
        isPresented: Binding(
          get: { model.queueInspectorIsPresented },
          set: { model.queueInspectorIsPresented = $0 })
      ) {
        Color.blue.inspectorColumnWidth(270)
      }
      .overlay(Color.black.opacity(model.showNowPlaying ? 0.5 : 0))
    }
  }

  func testOpeningPlayerWithQueueDoesNotReflowTheUnderlyingCatalog() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    model.showQueue = true
    let probe = LayoutProbe()
    let root = NSHostingView(rootView: InspectorFixture(model: model, probe: probe))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 1239, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = root
    defer { window.close() }
    func settle() async throws {
      for _ in 0..<15 {
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
      }
    }
    try await settle()
    let width = try XCTUnwrap(probe.view).bounds.width
    XCTAssertLessThan(width, 900, "The fixture must have a real, open native queue inspector")
    for expanded in [true, false, true, false] {
      model.showNowPlaying = expanded
      try await settle()
      XCTAssertEqual(
        try XCTUnwrap(probe.view).bounds.width, width, accuracy: 1,
        "The catalog behind a fading player must not jump when the queue inspector changes")
    }
  }

  func testBrowsingQueueKeepsVisibleEntryWhenPlaybackAdvancesAndOrderChanges() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    model.state.queue.replace(
      (0..<100).map {
        Track(platform: .wy, songID: "\($0)", title: "Song \($0)", artist: "Artist")
      }, start: 0)
    model.showQueue = true
    let host = NSHostingView(rootView: QueueView(inPlayer: false).environmentObject(model))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 260, height: 500), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() async throws {
      for _ in 0..<16 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    func find<T: NSView>(_ node: NSView, _ type: T.Type) -> T? {
      if let view = node as? T { return view }
      return node.subviews.lazy.compactMap { find($0, type) }.first
    }
    try await settle()
    let table = try XCTUnwrap(find(host, NSTableView.self))
    let scroll = try XCTUnwrap(table.enclosingScrollView)
    XCTAssertEqual(table.numberOfRows, 99)
    XCTAssertEqual(table.draggingDestinationFeedbackStyle, .gap)
    let id = model.state.queue.upcoming[30].id
    scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 30).minY + 3))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle()
    for _ in 0..<2 {
      XCTAssertTrue(model.state.queue.advance(automatic: true))
      try await settle()
      let index = try XCTUnwrap(model.state.queue.upcoming.firstIndex { $0.id == id })
      XCTAssertEqual(scroll.contentView.bounds.minY, table.rect(ofRow: index).minY + 3, accuracy: 1)
    }
    model.moveUpcoming(from: IndexSet(integer: 0), to: 40)
    try await settle()
    let index = try XCTUnwrap(model.state.queue.upcoming.firstIndex { $0.id == id })
    XCTAssertEqual(scroll.contentView.bounds.minY, table.rect(ofRow: index).minY + 3, accuracy: 1)
    XCTAssertLessThan(table.rows(in: scroll.contentView.bounds).length, 20)
  }

  func testQueueWidthPreferenceUsesCompactDefaultAndClampsSavedWidth() {
    let name = UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    XCTAssertEqual(QueueWidthPreference.width(in: defaults), 260)
    defaults.set(312, forKey: QueueWidthPreference.key)
    XCTAssertEqual(QueueWidthPreference.width(in: defaults), 312)
    defaults.set(900, forKey: QueueWidthPreference.key)
    XCTAssertEqual(QueueWidthPreference.width(in: defaults), 360)
  }

  func testInspectorStaysMountedUnderTheExpandedPlayer() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    model.showQueue = true
    XCTAssertTrue(model.queueInspectorIsPresented)
    model.showNowPlaying = true
    XCTAssertTrue(model.queueInspectorIsPresented)
    model.queueInspectorIsPresented = false
    XCTAssertTrue(
      model.showQueue, "A late inspector dismissal must not close the expanded player queue")
    model.showNowPlaying = false
    XCTAssertTrue(model.queueInspectorIsPresented, "Returning to browse restores its inspector")
    model.queueInspectorIsPresented = false
    XCTAssertFalse(model.showQueue)
  }
  func testQueueScrollbarsBlendWithBothQueueBackdrops() {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.identifier = NSUserInterfaceItemIdentifier("MyMusic.playerQueue")
    MusicScroller.apply(to: scroll)
    XCTAssertTrue((scroll.verticalScroller as? MusicScroller)?.blendsWithBackdrop == true)
    XCTAssertFalse(scroll.verticalScroller!.isOpaque)
    scroll.identifier = NSUserInterfaceItemIdentifier("MyMusic.sidebarQueue")
    MusicScroller.apply(to: scroll)
    XCTAssertTrue((scroll.verticalScroller as? MusicScroller)!.blendsWithBackdrop)
  }

  func testPlayerQueuePreservesBackdropAtOuterEdge() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    model.state.queue.replace(
      (1...40).map { Track(platform: .wy, songID: "\($0)", title: "Song \($0)", artist: "Artist") },
      start: 0)
    model.showNowPlaying = true
    model.showQueue = true
    let host = NSHostingView(
      rootView: ZStack {
        Color(red: 0.8, green: 0.12, blue: 0.1)
        QueueView().environmentObject(model)
      }.environment(\.colorScheme, .dark).frame(width: 360, height: 450))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 360, height: 450), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let color = try XCTUnwrap(
      bitmap.colorAt(x: 3, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
    let rail = try XCTUnwrap(
      bitmap.colorAt(x: bitmap.pixelsWide - 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(
        .deviceRGB))
    XCTAssertGreaterThan(
      rail.redComponent, rail.greenComponent * 1.5,
      "The scrollbar gutter must preserve the backdrop too")
    XCTAssertGreaterThan(
      color.redComponent, color.greenComponent * 1.5,
      "The player queue must let the red album backdrop show through, rather than painting an opaque sidebar surface"
    )
  }
}
