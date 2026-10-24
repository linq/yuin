import AppKit
import SwiftUI

/// Cover only the native divider's paint, retaining its resize hit target and layout.
struct SidebarDividerCover: NSViewRepresentable {
  var visible = true
  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ nsView: AnchorView, context: Context) {
    nsView.coverVisible = visible
    nsView.needsLayout = true
  }
  static func dismantleNSView(_ nsView: AnchorView, coordinator: ()) { nsView.detach() }

  final class AnchorView: NSView {
    var coverVisible = true { didSet { updateCover() } }
    private let cover = DividerView()
    private var observation: NSObjectProtocol?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      detach()
      guard window != nil else { return }
      observation = NotificationCenter.default.addObserver(
        forName: NSSplitView.didResizeSubviewsNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.updateCover() }
      needsLayout = true
    }

    override func layout() {
      super.layout()
      updateCover()
    }

    private func updateCover() {
      guard coverVisible else {
        cover.isHidden = true
        return
      }
      guard window != nil else { return }
      var ancestor = superview
      while let view = ancestor {
        if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count >= 2 {
          let panes = split.arrangedSubviews.sorted { $0.frame.minX < $1.frame.minX }
          let left = panes[0]
          let right = panes[1]
          guard !split.isSubviewCollapsed(left), left.frame.width > 1 else {
            cover.isHidden = true
            return
          }
          let width = max(0, right.frame.minX - left.frame.maxX)
          // Keep the paint inside the browser's native split. A window-level
          // sibling would appear above the player while its dismissal fades.
          if cover.superview !== split {
            // Preserve the existing panes while adding a non-layout decoration.
            split.arrangesAllSubviews = false
            split.addSubview(cover)
          }
          cover.frame = NSRect(
            x: left.frame.maxX, y: split.bounds.minY, width: width, height: split.bounds.height)
          cover.isHidden = width == 0
          cover.needsDisplay = true
          return
        }
        ancestor = view.superview
      }
      cover.isHidden = true
    }

    func detach() {
      if let observation { NotificationCenter.default.removeObserver(observation) }
      observation = nil
      cover.removeFromSuperview()
    }
  }

  private final class DividerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
      MusicSurface.content.setFill()
      bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
  }
}
