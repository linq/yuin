import AppKit
import SwiftUI

final class PageFocusScope {
  weak var start: NSView?
  weak var end: NSView?
  func contains(_ target: NSView) -> Bool {
    guard let start, let end, start.window === target.window else { return false }
    var parent = start.superview
    while let node = parent, !end.isDescendant(of: node) { parent = node.superview }
    guard let parent else { return false }
    var inside = false
    var finished = false
    var found = false
    func visit(_ view: NSView) {
      guard !finished, !found else { return }
      if view === start {
        inside = true
        return
      }
      if view === end {
        finished = true
        return
      }
      if inside, target === view || target.isDescendant(of: view) {
        found = true
        return
      }
      view.subviews.forEach(visit)
    }
    visit(parent)
    return found
  }
}

/// A retained page remembers its own table/editor without borrowing another page's focus.
struct PageFocusMemory: NSViewRepresentable {
  let scope: PageFocusScope
  let active: Bool
  let start: Bool
  func makeNSView(context: Context) -> Anchor {
    let view = Anchor()
    view.scope = scope
    view.tracksFocus = start
    if start { scope.start = view } else { scope.end = view }
    return view
  }
  func updateNSView(_ view: Anchor, context: Context) { if start { view.setActive(active) } }
  static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.detach() }
  final class Anchor: NSView {
    weak var scope: PageFocusScope?
    var tracksFocus = false
    private weak var remembered: NSView?
    private var active = true
    private var observer: NSObjectProtocol?
    func setActive(_ next: Bool) {
      if !next { capture() }
      let returning = next && !active
      active = next
      if returning {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.active, let view = self.remembered, let window = self.window,
            view.window === window, self.scope?.contains(view) == true
          else { return }
          window.makeFirstResponder(view)
        }
      }
    }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      detach()
      guard tracksFocus, let window else { return }
      observer = NotificationCenter.default.addObserver(
        forName: NSWindow.didUpdateNotification, object: window, queue: .main
      ) { [weak self] _ in self?.capture() }
    }
    private func capture() {
      guard active, var view = window?.firstResponder as? NSView else { return }
      if let editor = view as? NSTextView, editor.isFieldEditor,
        let control = editor.delegate as? NSView
      {
        view = control
      }
      if scope?.contains(view) == true { remembered = view }
    }
    func detach() {
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
    }
    deinit { detach() }
  }
}
