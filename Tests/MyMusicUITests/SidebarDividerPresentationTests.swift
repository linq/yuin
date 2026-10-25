import AppKit
import XCTest

@testable import MyMusic

@MainActor final class SidebarDividerPresentationTests: XCTestCase {
  func testRestoringDividerDuringPlayerDismissalStaysBelowPlayer() async throws {
    try await checkDismissal(appearance: .aqua)
    try await checkDismissal(appearance: .aqua, edge: .leading)
  }

  func testDarkPlayerDismissalAndDividerResize() async throws {
    try await checkDismissal(appearance: .darkAqua)
    try await checkDismissal(appearance: .darkAqua, edge: .leading)
  }

  private func checkDismissal(
    appearance: NSAppearance.Name, edge: SidebarDividerCover.Edge = .trailing
  ) async throws {
    _ = NSApplication.shared
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    let split = NSSplitView(frame: root.bounds)
    split.isVertical = true
    split.dividerStyle = .thin
    let sidebar = NSView()
    let detail = PlayerSurface()
    detail.color = MusicSurface.content
    split.addArrangedSubview(sidebar)
    split.addArrangedSubview(detail)
    root.addSubview(split)
    let anchor = SidebarDividerCover.AnchorView(frame: .zero)
    anchor.edge = edge
    anchor.coverVisible = false
    (edge == .trailing ? sidebar : detail).addSubview(anchor)
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 500, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearance)
    window.contentView = root
    defer { window.close() }
    split.adjustSubviews()
    split.setPosition(200, ofDividerAt: 0)
    // The player is still visible on the first frame of its dismissal fade.
    let player = PlayerSurface(frame: root.bounds)
    root.addSubview(player)
    for position in [200.0, 230, 200] {
      anchor.coverVisible = false
      split.setPosition(position, ofDividerAt: 0)
      anchor.coverVisible = true
      anchor.needsLayout = true
      root.layoutSubtreeIfNeeded()
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
      let (pixel, backdrop) = try dividerPixels(root: root, split: split, sidebar: sidebar)
      assertSameColor(pixel, backdrop, "The divider must stay below the fading player")
      XCTAssertEqual(split.arrangedSubviews.count, 2, "The cover must not become a third pane")
      XCTAssertEqual(sidebar.frame.width, position, accuracy: 1)
    }
    player.removeFromSuperview()
    let (pixel, content) = try dividerPixels(root: root, split: split, sidebar: sidebar)
    assertSameColor(pixel, content, "The restored divider must blend into the browser surface")
    let dividerPoint = NSPoint(
      x: sidebar.frame.maxX + split.dividerThickness / 2, y: split.bounds.midY)
    XCTAssertTrue(split.hitTest(dividerPoint) === split, "The divider must remain draggable")
  }

  private func assertSameColor(
    _ actual: NSColor, _ expected: NSColor, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(
      actual.redComponent, expected.redComponent, accuracy: 0.02, message, file: file, line: line)
    XCTAssertEqual(
      actual.greenComponent, expected.greenComponent, accuracy: 0.02, message, file: file,
      line: line)
    XCTAssertEqual(
      actual.blueComponent, expected.blueComponent, accuracy: 0.02, message, file: file, line: line)
  }

  private func dividerPixels(root: NSView, split: NSSplitView, sidebar: NSView) throws -> (
    NSColor, NSColor
  ) {
    let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
    root.effectiveAppearance.performAsCurrentDrawingAppearance {
      root.displayIfNeeded()
      root.cacheDisplay(in: root.bounds, to: bitmap)
    }
    let scale = CGFloat(bitmap.pixelsWide) / root.bounds.width
    let dividerX = sidebar.frame.maxX + split.dividerThickness / 2
    let divider = try XCTUnwrap(
      bitmap.colorAt(x: Int(dividerX * scale), y: bitmap.pixelsHigh / 2)?
        .usingColorSpace(.sRGB))
    // Compare pixels from the same render to avoid display-profile/HDR conversion differences.
    let backdrop = try XCTUnwrap(
      bitmap.colorAt(x: bitmap.pixelsWide - 10, y: bitmap.pixelsHigh / 2)?
        .usingColorSpace(.sRGB))
    return (divider, backdrop)
  }

  private final class PlayerSurface: NSView {
    var color = NSColor(srgbRed: 0.8, green: 0.12, blue: 0.1, alpha: 1)
    override func draw(_ dirtyRect: NSRect) {
      color.setFill()
      bounds.fill()
    }
  }
}
