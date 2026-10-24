import AppKit
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class PlayerPagePresentationTests: XCTestCase {
  func testCoveredCatalogStaysPaintedThroughoutPlayerFade() throws {
    _ = NSApplication.shared
    // Use the same retained-page boundary as the catalog grid. Red stands for
    // cover content, blue for the player, white for an exposed empty browser.
    func pixel(covered: Bool, alpha: Double) throws -> NSColor {
      let view = Color.red
        .modifier(RetainedPage(active: true, covered: covered))
        .background(Color.white)
        .overlay(Color.blue.opacity(alpha))
        .frame(width: 100, height: 100)
      let host = NSHostingView(rootView: view)
      host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      return try XCTUnwrap(bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
    }
    for covered in [false, true, false, true] {
      for alpha in [0.0, 0.25, 0.5, 0.75, 1.0] {
        let actual = try pixel(covered: covered, alpha: alpha)
        let expected = try pixel(covered: false, alpha: alpha)
        XCTAssertEqual(
          actual.greenComponent, expected.greenComponent, accuracy: 0.02,
          "A partially transparent player must reveal the catalog, never the empty browser")
      }
    }
  }
}
