import AppKit
import XCTest

@testable import MyMusic

@MainActor final class NavigationToolbarRenderingTests: XCTestCase {
  private final class FlippedView: NSView { override var isFlipped: Bool { true } }
  private final class BlueDocument: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
      NSColor.white.setFill()
      bounds.fill()
      NSColor.blue.setFill()
      NSRect(x: 20, y: 0, width: bounds.width - 40, height: 200).fill()
    }
  }
  private final class RedHeader: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
      NSColor.red.setFill()
      bounds.fill()
    }
  }

  func testWhiteBaseAndBlurFollowOnlyThePassingDocumentAndSupplementaryHeader() async throws {
    _ = NSApplication.shared
    try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let window = NSWindow(
      contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = root
    defer { window.close() }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 52, width: 600, height: 348))
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentView.automaticallyAdjustsContentInsets = false
    scroll.documentView = BlueDocument(frame: NSRect(x: 0, y: 0, width: 600, height: 1400))
    root.addSubview(scroll)
    let toolbar = NavigationToolbarBlurView(frame: NSRect(x: 0, y: 0, width: 600, height: 52))
    root.addSubview(toolbar)
    toolbar.attach(scroll)
    func settle() async throws {
      root.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
    }
    func pixel() throws -> NSColor {
      let bitmap = try XCTUnwrap(toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds))
      toolbar.cacheDisplay(in: toolbar.bounds, to: bitmap)
      return try XCTUnwrap(
        bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }
    try await settle()
    let blank = try pixel()
    XCTAssertGreaterThan(blank.redComponent, 0.99, "A blank light toolbar must match white content")
    XCTAssertGreaterThan(blank.greenComponent, 0.99)
    XCTAssertGreaterThan(blank.blueComponent, 0.99)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 140))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle()
    let blue = try pixel()
    XCTAssertGreaterThan(
      blue.blueComponent - blue.redComponent, 0.15, "Passing artwork must tint the header")
    XCTAssertGreaterThan(
      blue.redComponent, 0.6, "The toolbar must soften, not duplicate opaque artwork")
    let count = toolbar.captureCount
    try await settle()
    XCTAssertEqual(toolbar.captureCount, count, "An idle toolbar must stop capturing")

    // Album details host their artwork beside the native table, above row zero.
    MusicTableClipView.install(in: scroll)
    let clip = try XCTUnwrap(scroll.contentView as? MusicTableClipView)
    clip.headerHeight = 120
    let header = RedHeader(frame: NSRect(x: 0, y: -120, width: 600, height: 120))
    clip.addSubview(header)
    toolbar.attach(nil)
    toolbar.attach(scroll)
    clip.scroll(to: NSPoint(x: 0, y: -60))
    scroll.reflectScrolledClipView(clip)
    try await settle()
    let red = try pixel()
    XCTAssertGreaterThan(
      red.redComponent - red.blueComponent, 0.15,
      "Supplementary album artwork must also reach the toolbar")
    toolbar.attach(nil)
    try await settle()
    XCTAssertGreaterThan(
      try pixel().greenComponent, 0.99, "Leaving a catalog must clear its old tint")
    window.appearance = NSAppearance(named: .darkAqua)
    try await settle()
    XCTAssertLessThan(
      try pixel().redComponent, 0.25, "Dark mode must retain the system content base")
  }
}
