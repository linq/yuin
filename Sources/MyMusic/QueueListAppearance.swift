import AppKit
import SwiftUI

/// Native List keeps queue reordering and keyboard behavior. Its scroll surface
/// must blend into the album backdrop when embedded in the full-window player.
struct QueueListAppearance: NSViewRepresentable {
  let player: Bool
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.player = player
    view.needsLayout = true
  }
  final class Anchor: NSView {
    var player = false
    private var scheduled = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.configure() }
    }
    override func layout() {
      super.layout()
      guard !scheduled else { return }
      scheduled = true
      DispatchQueue.main.async { [weak self] in
        self?.scheduled = false
        self?.configure()
      }
    }
    private func configure() {
      guard window != nil else { return }
      func find(_ node: NSView) -> NSScrollView? {
        if let scroll = node as? NSScrollView { return scroll }
        for child in node.subviews where child !== self {
          if let found = find(child) { return found }
        }
        return nil
      }
      var parent = superview
      while let node = parent {
        if let scroll = find(node) {
          scroll.identifier = NSUserInterfaceItemIdentifier(
            player ? "MyMusic.playerQueue" : "MyMusic.sidebarQueue")
          scroll.drawsBackground = false
          if player {
            if scroll.appearance?.name != .darkAqua {
              scroll.appearance = NSAppearance(named: .darkAqua)
            }
          } else if scroll.appearance != nil {
            scroll.appearance = nil
          }
          func clearTables(_ node: NSView) {
            if let table = node as? NSTableView {
              if table.backgroundColor != .clear { table.backgroundColor = .clear }
              if table.usesAlternatingRowBackgroundColors {
                table.usesAlternatingRowBackgroundColors = false
              }
              return
            }
            for child in node.subviews { clearTables(child) }
          }
          if let document = scroll.documentView { clearTables(document) }
          MusicScroller.apply(to: scroll)
          return
        }
        parent = node.superview
      }
    }
  }
}
