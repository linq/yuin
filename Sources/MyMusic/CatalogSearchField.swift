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
  func makeNSView(context: Context) -> SearchField {
    let field = SearchField()
    field.placeholderString = placeholder
    field.focusesOnAppear = focusesOnAppear
    field.setAccessibilityLabel(accessibilityName)
    field.font = .systemFont(ofSize: 13)
    field.controlSize = .large
    field.sendsWholeSearchString = true
    field.sendsSearchStringImmediately = false
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.search(_:))
    return field
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
