import AppKit
import MusicCore
import SwiftUI

/// A toolbar search field uses the window's responder chain, including when reinserted after navigation.
struct CatalogSearchField: NSViewRepresentable {
  @Environment(\.locale) private var locale
  @Binding var text: String
  let focusRequest: Int
  var placeholder = L10n.text("歌曲、歌手或专辑")
  var accessibilityName = L10n.text("搜索音乐")
  var focusesOnAppear = true
  let submit: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: SearchField, context: Context) -> CGSize?
  {
    CGSize(width: proposal.width ?? 320, height: proposal.height ?? 38)
  }
  func makeNSView(context: Context) -> SearchField {
    let field = SearchField()
    field.cell = SearchCell(textCell: "")
    field.isBezeled = false
    field.drawsBackground = false
    field.isEditable = true
    field.isSelectable = true
    field.placeholderString = placeholder
    field.focusesOnAppear = focusesOnAppear
    field.setAccessibilityLabel(accessibilityName)
    field.font = .systemFont(ofSize: 15)
    field.controlSize = .large
    field.sendsWholeSearchString = true
    field.sendsSearchStringImmediately = false
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.search(_:))
    return field
  }

  final class SearchCell: NSSearchFieldCell {
    override func draw(withFrame frame: NSRect, in controlView: NSView) {
      let shape = NSBezierPath(
        roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
        xRadius: frame.height / 2, yRadius: frame.height / 2)
      NSColor.controlBackgroundColor.withAlphaComponent(0.65).setFill()
      shape.fill()
      NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
      shape.lineWidth = 0.5
      shape.stroke()
      super.draw(withFrame: frame, in: controlView)
    }
    override func drawFocusRingMask(withFrame frame: NSRect, in controlView: NSView) {
      NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
    }
    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
      NSRect(x: rect.minX + 12, y: rect.midY - 9, width: 18, height: 18)
    }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
      NSRect(x: rect.maxX - 28, y: rect.midY - 8, width: 16, height: 16)
    }
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
      NSRect(x: rect.minX + 38, y: rect.midY - 10, width: max(0, rect.width - 70), height: 21)
    }
    override func select(
      withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
      delegate: Any?, start selStart: Int, length selLength: Int
    ) {
      super.select(
        withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
        delegate: delegate, start: selStart, length: selLength)
    }
    override func edit(
      withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
      delegate: Any?, event: NSEvent?
    ) {
      super.edit(
        withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
        delegate: delegate, event: event)
    }
  }
  func updateNSView(_ field: SearchField, context: Context) {
    field.placeholderString = placeholder
    field.setAccessibilityLabel(accessibilityName)
    context.coordinator.parent = self
    if field.stringValue != text { field.stringValue = text }
    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      if focusesOnAppear || focusRequest > 0 { field.requestFocus() }
    }
  }

  final class SearchField: NSSearchField {
    var focusesOnAppear = true
    override var intrinsicContentSize: NSSize {
      NSSize(width: super.intrinsicContentSize.width, height: 38)
    }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil && focusesOnAppear { requestFocus() }
    }
    func requestFocus() {
      DispatchQueue.main.async { [weak self] in
        guard let self, let window = self.window else { return }
        window.makeFirstResponder(self)
        self.selectText(nil)
      }
    }
  }
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: CatalogSearchField
    var lastFocusRequest: Int?
    init(parent: CatalogSearchField) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      if let field = notification.object as? NSSearchField { parent.text = field.stringValue }
    }
    @objc func search(_ sender: NSSearchField) {
      parent.text = sender.stringValue
      parent.submit()
    }
  }
}
