import AppKit
import XCTest

@testable import MyMusic

@MainActor final class AppearanceTests: XCTestCase {
  func testSidebarRepairsOldNarrowWidthAndKeepsUserExpansion() async {
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 1239, height: 600)
    let window = NSWindow(
      contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let split = NSSplitView(frame: frame)
    split.isVertical = true
    let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 144, height: 600))
    split.addArrangedSubview(sidebar)
    split.addArrangedSubview(NSView(frame: NSRect(x: 145, y: 0, width: 1094, height: 600)))
    window.contentView = split
    split.setPosition(144, ofDividerAt: 0)
    let anchor = SidebarWidthAnchor.Anchor(frame: sidebar.bounds)
    sidebar.addSubview(anchor)
    func settle() async {
      anchor.needsLayout = true
      anchor.layoutSubtreeIfNeeded()
      for _ in 0..<4 {
        await withCheckedContinuation { continuation in
          DispatchQueue.main.async { continuation.resume() }
        }
      }
    }
    await settle()
    XCTAssertEqual(sidebar.frame.width, 200, accuracy: 1)
    split.setPosition(240, ofDividerAt: 0)
    await settle()
    XCTAssertEqual(sidebar.frame.width, 240, accuracy: 1)
  }

  func testAppearanceModesAndAutomaticSystemReset() {
    _ = NSApplication.shared
    let original = NSApp.appearance
    defer { NSApp.appearance = original }
    MusicAppearance.light.apply()
    XCTAssertEqual(NSApp.appearance?.name, .aqua)
    XCTAssertEqual(MusicAppearance.light.colorScheme, .light)
    MusicAppearance.dark.apply()
    XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
    XCTAssertEqual(MusicAppearance.dark.colorScheme, .dark)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.appearance = NSAppearance(named: .darkAqua)
    MusicAppearance.system.apply()
    XCTAssertNil(window.appearance)
    XCTAssertNil(NSApp.appearance)
    XCTAssertNil(MusicAppearance.system.colorScheme)
    func brightness(_ name: NSAppearance.Name) -> CGFloat {
      var value: CGFloat = 0
      NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        value = MusicSurface.content.usingColorSpace(.deviceRGB)!.redComponent
      }
      return value
    }
    XCTAssertGreaterThan(brightness(.aqua), 0.9)
    XCTAssertLessThan(brightness(.darkAqua), 0.2)
  }

  func testLyricsHideTheirRailWithoutHidingOtherPageScrollbars() {
    let lyrics = NSScrollView()
    lyrics.identifier = NSUserInterfaceItemIdentifier("MyMusic.synchronizedLyrics")
    lyrics.hasVerticalScroller = true
    let catalog = NSScrollView()
    catalog.hasVerticalScroller = true
    MusicScroller.apply(to: lyrics)
    MusicScroller.apply(to: catalog)
    XCTAssertFalse(lyrics.hasVerticalScroller)
    XCTAssertTrue(catalog.hasVerticalScroller)
    XCTAssertTrue(catalog.verticalScroller is MusicScroller)
  }

  func testWindowTreeStylesAllScrollAreasAndRecreatedScrollers() {
    let root = NSView()
    let container = NSView()
    root.addSubview(container)
    let areas = (0..<4).map { _ -> NSScrollView in
      let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
      scroll.hasVerticalScroller = true
      scroll.borderType = .lineBorder
      container.addSubview(scroll)
      return scroll
    }
    MusicScroller.applyTree(to: root)
    for scroll in areas {
      XCTAssertTrue(scroll.verticalScroller is MusicScroller)
      XCTAssertEqual(scroll.borderType, .noBorder)
      XCTAssertEqual(scroll.scrollerStyle, NSScroller.preferredScrollerStyle)
    }
    areas[2].verticalScroller = NSScroller()
    MusicScroller.applyTree(to: root)
    XCTAssertTrue(areas[2].verticalScroller is MusicScroller)
  }
}
