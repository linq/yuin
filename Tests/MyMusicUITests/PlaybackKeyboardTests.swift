import AppKit
import XCTest

@testable import MyMusic

@MainActor final class PlaybackKeyboardTests: XCTestCase {
  func testExpandedPlayerHandlesSpaceEvenWhenCoveredSearchRetainsItsEditor() throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 400, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    window.contentView = root
    let field = NSSearchField(frame: NSRect(x: 10, y: 10, width: 200, height: 30))
    root.addSubview(field)
    window.makeFirstResponder(field)
    let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
    XCTAssertTrue(editor.isEditable)
    let shortcut = PlaybackKeyboardShortcuts.ShortcutView()
    root.addSubview(shortcut)
    var toggles = 0
    shortcut.toggle = { toggles += 1 }
    func key(
      _ modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false,
      number: Int? = nil
    ) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: modifiers,
          timestamp: 0, windowNumber: number ?? window.windowNumber, context: nil,
          characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeatKey, keyCode: 49))
    }
    let space = try key()
    XCTAssertNotNil(shortcut.handle(space), "Search editing must receive a normal space")
    XCTAssertEqual(toggles, 0)
    shortcut.expanded = true
    field.isHidden = true
    XCTAssertNil(shortcut.handle(space), "The covered editor must not steal the player shortcut")
    XCTAssertEqual(toggles, 1)
    XCTAssertNil(shortcut.handle(try key(repeatKey: true)))
    XCTAssertEqual(toggles, 1, "Holding Space must not toggle playback repeatedly")
    XCTAssertNotNil(shortcut.handle(try key(.command)))
    XCTAssertNotNil(shortcut.handle(try key(.option)))
    XCTAssertEqual(toggles, 1)
    shortcut.expanded = false
    field.isHidden = false
    window.makeFirstResponder(field)
    XCTAssertNotNil(shortcut.handle(space))
    XCTAssertEqual(toggles, 1)
    let other = NSWindow(
      contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    other.isReleasedWhenClosed = false
    defer { other.close() }
    shortcut.expanded = true
    XCTAssertNotNil(shortcut.handle(try key(number: other.windowNumber)))
    XCTAssertEqual(toggles, 1, "Settings and other windows must not trigger this player")
  }
}
