import AppKit
import SwiftUI

/// Cover only the native divider's paint, retaining its resize hit target and layout.
struct SidebarDividerCover: NSViewRepresentable {
  enum Edge { case leading, trailing }
  var visible = true
  var edge: Edge = .trailing
  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ nsView: AnchorView, context: Context) {
    nsView.edge = edge
    nsView.coverVisible = visible
    nsView.needsLayout = true
  }
  static func dismantleNSView(_ nsView: AnchorView, coordinator: ()) { nsView.detach() }

  final class AnchorView: NSView {
    var edge: Edge = .trailing
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
      var child: NSView = self
      var ancestor = superview
      while let view = ancestor {
        if let split = view as? NSSplitView, split.isVertical,
          split.arrangedSubviews.count >= 2, split.arrangedSubviews.contains(child)
        {
          guard !split.isSubviewCollapsed(child), child.frame.width > 1 else {
            cover.isHidden = true
            return
          }
          // SwiftUI extends the detail pane underneath both adjacent columns.
          // There may be no gap between arranged frames even though AppKit
          // still paints a divider. Follow this anchor's own column edge.
          let pixel = 1 / (window?.backingScaleFactor ?? 2)
          let width = max(pixel, split.dividerThickness)
          let x = edge == .trailing ? child.frame.maxX : child.frame.minX - width
          guard let parent = split.superview else { return }
          // AppKit regenerates divider/shadow views inside the split. Paint
          // immediately above that native subtree, below later player siblings.
          // The decoration never participates in the split's pane layout.
          if cover.superview !== parent {
            cover.removeFromSuperview()
            parent.addSubview(cover, positioned: .above, relativeTo: split)
          }
          let localFrame = NSRect(
            x: x - pixel, y: split.bounds.minY, width: width + 2 * pixel,
            height: split.bounds.height)
          let frame = parent.convert(localFrame, from: split)
          if cover.frame != frame {
            cover.frame = frame
            cover.needsDisplay = true
          }
          cover.isHidden = false
          return
        }
        child = view
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
    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
      MusicSurface.content.setFill()
      bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
  }
}
