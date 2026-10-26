import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class QueueMaterialRenderingTests: XCTestCase {
  private struct WindowFixture: View {
    @ObservedObject var model: AppModel
    var body: some View {
      NavigationSplitView {
        Color.gray.navigationSplitViewColumnWidth(200)
      } detail: {
        Color.gray.toolbar { Text("Catalog") }
      }
      .inspector(isPresented: .constant(true)) {
        QueueView(inPlayer: false).environmentObject(model).inspectorColumnWidth(300)
      }
      .toolbarBackground(.hidden, for: .windowToolbar)
    }
  }

  func testInspectorBackdropCoversTheWindowTopAndFirstSongClearsControls() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    model.state.queue.replace(
      (0..<40).map { Track(platform: .wy, songID: "\($0)", title: "Song \($0)", artist: "Artist") },
      start: 0)
    model.showQueue = true
    let host = NSHostingView(rootView: WindowFixture(model: model))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 1000, height: 600),
      styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.toolbar = NSToolbar(identifier: "QueueFixture")
    window.toolbarStyle = .unified
    window.contentView = host
    defer { window.close() }
    for _ in 0..<40 {
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(10))
    }
    func find<T: NSView>(_ node: NSView, _ type: T.Type) -> T? {
      if let view = node as? T { return view }
      return node.subviews.lazy.compactMap { find($0, type) }.first
    }
    let backdrop = try XCTUnwrap(find(host, QueueHeaderBackdrop.self))
    let backdropRect = host.convert(backdrop.bounds, from: backdrop)
    XCTAssertLessThanOrEqual(
      backdropRect.minY, 1, "The queue blur must also cover the strip beside the window toolbar")
    XCTAssertLessThanOrEqual(
      backdropRect.height, 100,
      "Queue controls must start near the window top rather than reserve a second toolbar band")
    let table = try XCTUnwrap(find(host, NSTableView.self))
    let first = host.convert(table.rect(ofRow: 0), from: table)
    XCTAssertGreaterThanOrEqual(first.minY, backdropRect.maxY - 1)
  }

  func testEmptyHeaderPreservesTheUnderlyingQueueSurface() async throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 300, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    window.contentView = root
    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
    table.backgroundColor = .clear
    root.addSubview(table)
    let backdrop = QueueHeaderBackdrop(frame: NSRect(x: 0, y: 0, width: 300, height: 92))
    root.addSubview(backdrop)
    let bodySurface = NSHostingView(rootView: Rectangle().fill(MusicSurface.navigationMaterial))
    bodySurface.frame = NSRect(x: 0, y: 100, width: 300, height: 92)
    root.addSubview(bodySurface)
    for name in [NSAppearance.Name.aqua, .darkAqua] {
      window.appearance = NSAppearance(named: name)
      backdrop.update(table: table, rect: NSRect(x: 0, y: -92, width: 300, height: 92))
      try await Task.sleep(for: .milliseconds(100))
      func sample(_ view: NSView) throws -> NSColor {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))
      }
      let header = try sample(backdrop)
      let body = try sample(bodySurface)
      for (actual, expected) in zip(
        [header.redComponent, header.greenComponent, header.blueComponent, header.alphaComponent],
        [body.redComponent, body.greenComponent, body.blueComponent, body.alphaComponent])
      {
        XCTAssertEqual(
          actual, expected, accuracy: 0.02,
          "An empty header must match the queue body's material, without its own white tint in \(name)"
        )
      }
    }
  }

  func testHeaderActuallyReceivesTheContentScrollingBehindIt() async throws {
    _ = NSApplication.shared
    try XCTSkipIf(
      NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
      "Transparency is intentionally disabled by the system accessibility preference")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    model.state.queue.replace(
      (0..<60).map {
        Track(
          platform: .wy, songID: "\($0)",
          title: $0.isMultiple(of: 2) ? String(repeating: "█", count: 40) : "", artist: "")
      }, start: 0)
    model.showQueue = true
    let host = NSHostingView(rootView: QueueView(inPlayer: false).environmentObject(model))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 300, height: 500), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() async throws {
      for _ in 0..<20 {
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
    func sample(row: Int) async throws -> Double {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: row).minY - 8))
      scroll.reflectScrolledClipView(scroll.contentView)
      try await settle()
      // List revises estimated row heights after bringing these rows on screen.
      scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: row).minY - 8))
      scroll.reflectScrolledClipView(scroll.contentView)
      try await settle()
      let rect = NSRect(x: 100, y: 24, width: 14, height: 16)
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: rect))
      host.cacheDisplay(in: rect, to: bitmap)
      var sum = 0.0
      for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
          let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
          sum += (color.redComponent + color.greenComponent + color.blueComponent) / 3
        }
      }
      return sum / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
    }
    for appearance in [NSAppearance.Name.darkAqua, .aqua] {
      window.appearance = NSAppearance(named: appearance)
      try await settle()
      let bright = try await sample(row: 19)
      let dark = try await sample(row: 20)
      XCTAssertGreaterThan(
        abs(bright - dark), 0.025,
        "The header must visibly transmit blurred content in \(appearance): \(bright), \(dark)")
    }
    let backdrop = try XCTUnwrap(
      scroll.contentView.subviews.compactMap { $0 as? QueueHeaderBackdrop }.first)
    XCTAssertGreaterThan(
      backdrop.captureCount, 0,
      "The live header must contain rendered content, not only a material style")
    let count = backdrop.captureCount
    try await settle()
    XCTAssertEqual(
      backdrop.captureCount, count, "A stationary queue must not keep capturing its backdrop")
    for _ in 0..<100 {
      backdrop.update(table: table, rect: table.convert(backdrop.frame, from: scroll.contentView))
    }
    try await settle()
    XCTAssertLessThanOrEqual(
      backdrop.captureCount, count + 1, "Coalesce repeated invalidations into one bounded capture")
  }
}
