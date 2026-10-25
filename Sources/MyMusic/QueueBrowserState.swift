import AppKit
import SwiftUI

/// Only the browser inspector owns this preference; the full-window queue has a different layout.
enum QueueWidthPreference {
  static let key = "queueInspectorWidth"
  static func width(in defaults: UserDefaults = .standard) -> CGFloat {
    let saved = defaults.double(forKey: key)
    return saved.isFinite && saved >= 240 ? min(360, saved) : 260
  }
}

struct QueueWidthMemory: NSViewRepresentable {
  let active: Bool
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) { view.active = active }
  final class Anchor: NSView {
    var active = true
    override func layout() {
      super.layout()
      guard active, window != nil, bounds.width >= 240, bounds.width <= 360 else { return }
      if abs(UserDefaults.standard.double(forKey: QueueWidthPreference.key) - bounds.width) > 1 {
        UserDefaults.standard.set(bounds.width, forKey: QueueWidthPreference.key)
      }
    }
  }
}
