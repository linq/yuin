import AppKit
import SwiftUI

/// NavigationSplitView may restore an obsolete native width below its SwiftUI minimum.
struct SidebarWidthAnchor: NSViewRepresentable {
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) { view.needsLayout = true }
  final class Anchor: NSView {
    private var scheduled = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      needsLayout = true
    }
    override func layout() {
      super.layout()
      guard !scheduled, window != nil else { return }
      scheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.scheduled = false
        var ancestor = self.superview
        while let view = ancestor {
          if let split = view as? NSSplitView, split.isVertical,
            split.arrangedSubviews.count >= 2, let sidebar = split.arrangedSubviews.first,
            !split.isSubviewCollapsed(sidebar), sidebar.frame.width < 199.5
          {
            split.setPosition(200, ofDividerAt: 0)
            return
          }
          ancestor = view.superview
        }
      }
    }
  }
}
