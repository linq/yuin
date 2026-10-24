import AppKit
import SwiftUI

/// A window-scoped shortcut precedes the first responder. The covered search
/// field can retain its editor even though it is absent from the player UI.
struct PlaybackKeyboardShortcuts: NSViewRepresentable {
  let expanded: Bool
  let toggle: () -> Void
  func makeNSView(context: Context) -> ShortcutView { ShortcutView() }
  func updateNSView(_ nsView: ShortcutView, context: Context) {
    nsView.expanded = expanded
    nsView.toggle = toggle
  }
  static func dismantleNSView(_ nsView: ShortcutView, coordinator: ()) { nsView.detach() }

  final class ShortcutView: NSView {
    var expanded = false
    var toggle: (() -> Void)?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      detach()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }
        return self.handle(event)
      }
    }
    func handle(_ event: NSEvent) -> NSEvent? {
      guard let window, event.window === window, window.attachedSheet == nil,
        event.type == .keyDown, event.charactersIgnoringModifiers == " ",
        event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
      else { return event }
      if !expanded {
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return event }
        if window.firstResponder is NSTextField { return event }
      }
      if !event.isARepeat { toggle?() }
      return nil
    }
    func detach() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
    deinit { detach() }
  }
}
