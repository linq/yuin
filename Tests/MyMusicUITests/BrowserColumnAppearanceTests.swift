import AppKit
import MusicCore
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class BrowserColumnAppearanceTests: XCTestCase {
  func testRealBrowserHasNoDarkRulesAtEitherColumnBoundary() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let savedWidth = UserDefaults.standard.object(forKey: QueueWidthPreference.key)
    defer { UserDefaults.standard.set(savedWidth, forKey: QueueWidthPreference.key) }
    let model = AppModel(
      store: LibraryStore(url: directory.appendingPathComponent("library.json")),
      startServices: false)
    model.showQueue = true
    let host = NSHostingView(rootView: ContentView().environmentObject(model))
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 1239, height: 600),
      styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() async throws {
      for _ in 0..<30 {
        host.layoutSubtreeIfNeeded()
        window.update()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    func splits(_ node: NSView) -> [NSSplitView] {
      ((node as? NSSplitView).map { [$0] } ?? []) + node.subviews.flatMap(splits)
    }
    try await settle()
    let columns = splits(host).filter { $0.isVertical && $0.arrangedSubviews.count >= 2 }
    XCTAssertEqual(columns.count, 2, "Exercise both the sidebar split and the real queue inspector")
    for appearance in [NSAppearance.Name.darkAqua, .aqua] {
      window.appearance = NSAppearance(named: appearance)
      try await settle()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
      func brightness(x: CGFloat, y: CGFloat) throws -> CGFloat {
        let color = try XCTUnwrap(
          bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
      }
      for split in columns {
        // SwiftUI stretches its detail pane beneath adjacent columns. The
        // narrow sidebar/inspector pane defines the visible boundary, not a gap.
        let pane = try XCTUnwrap(split.arrangedSubviews.first { $0.frame.width <= 360 })
        let x = pane.frame.minX < 1 ? pane.frame.maxX : pane.frame.minX
        let edge = host.convert(NSPoint(x: x, y: 0), from: split).x
        for y in [200.0, 350, 470] {
          let left = try brightness(x: edge - 2, y: y)
          let right = try brightness(x: edge + 2, y: y)
          for offset in [-1.0, -0.5, 0, 0.5] {
            let line = try brightness(x: edge + offset, y: y)
            XCTAssertGreaterThanOrEqual(
              line, min(left, right) - 0.025,
              "A column boundary must not add a dark rule at x=\(edge + offset), y=\(y) in \(appearance)"
            )
          }
        }
      }
    }
  }
}
