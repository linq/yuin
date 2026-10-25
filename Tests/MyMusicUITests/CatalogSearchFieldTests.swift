import AppKit
import XCTest

@testable import MyMusic

@MainActor final class CatalogSearchFieldTests: XCTestCase {
  func testLargeSearchEditorKeepsTextBetweenSearchAndCancelButtons() throws {
    _ = NSApplication.shared
    let field = CatalogSearchField.SearchField(frame: NSRect(x: 0, y: 0, width: 360, height: 38))
    field.cell = CatalogSearchField.SearchCell(textCell: "")
    field.isBezeled = false
    field.isEditable = true
    field.isSelectable = true
    field.font = .systemFont(ofSize: 15)
    field.stringValue = "周杰伦"
    let window = NSWindow(
      contentRect: NSRect(x: -5000, y: -5000, width: 360, height: 38),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = field
    defer { window.close() }
    window.makeFirstResponder(field)
    field.selectText(nil)
    let editor = try XCTUnwrap(field.currentEditor())
    let rect = editor.convert(editor.bounds, to: field)
    XCTAssertGreaterThanOrEqual(rect.minX, 34)
    XCTAssertLessThanOrEqual(rect.maxX, field.bounds.width - 28)
    XCTAssertEqual(rect.midY, field.bounds.midY, accuracy: 2)
    XCTAssertEqual(field.intrinsicContentSize.height, 38)
  }
}
