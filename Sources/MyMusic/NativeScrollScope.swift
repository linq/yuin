import AppKit
import SwiftUI

/// SwiftUI can flatten several retained pages into one AppKit parent. Explicit
/// boundaries keep native adapters attached to their own scroll view, even when
/// an overlapping page has exactly the same frame.
final class NativeScrollScope {
  weak var start: NSView?
  weak var end: NSView?
  private weak var cached: NSScrollView?

  func resolve(table: Bool) -> NSScrollView? {
    guard let start, let end, start.window != nil, start.window === end.window else { return nil }
    if let cached, cached.window === start.window { return cached }
    var ancestor: NSView? = start.superview
    while let parent = ancestor, !end.isDescendant(of: parent) { ancestor = parent.superview }
    guard let ancestor else { return nil }
    var inside = false
    var finished = false
    var result: NSScrollView?
    func containsTable(_ view: NSView?) -> Bool {
      guard let view else { return false }
      return view is NSTableView || view.subviews.contains { containsTable($0) }
    }
    func visit(_ view: NSView) {
      guard !finished, result == nil else { return }
      if view === start {
        inside = true
        return
      }
      if view === end {
        finished = true
        return
      }
      if inside, let scroll = view as? NSScrollView,
        containsTable(scroll.documentView) == table
      {
        result = scroll
        return
      }
      for child in view.subviews { visit(child) }
    }
    visit(ancestor)
    if table, let result { MusicTableClipView.install(in: result) }
    cached = result
    return result
  }
  func invalidate() { cached = nil }
}

struct NativeScrollBoundary: NSViewRepresentable {
  let scope: NativeScrollScope
  let isStart: Bool
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    if isStart { scope.start = view } else { scope.end = view }
    scope.invalidate()
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}

/// Extends the document's scrollable range above its rows without using a
/// content inset, which AppKit treats as a permanent noninteractive top band.
final class MusicTableClipView: NSClipView {
  var headerHeight: CGFloat = 0
  var bottomClearance: CGFloat = 0
  override var documentRect: NSRect {
    var rect = super.documentRect
    rect.origin.y -= headerHeight
    rect.size.height += headerHeight
    if bottomClearance > 0, let table = documentView as? NSTableView, table.numberOfRows > 0 {
      let lastRowEnd = table.rect(ofRow: table.numberOfRows - 1).maxY
      rect.size.height = max(rect.height, lastRowEnd + bottomClearance - rect.minY)
    }
    return rect
  }
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposedBounds)
    if headerHeight > 0, proposedBounds.minY < 0 {
      rect.origin.y = max(-headerHeight, proposedBounds.minY)
    }
    if bottomClearance > 0, proposedBounds.minY > rect.minY {
      let limit = max(documentRect.minY, documentRect.maxY - proposedBounds.height)
      rect.origin.y = min(limit, proposedBounds.minY)
    }
    return rect
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    if let target = super.hitTest(point) { return target }
    guard let superview else { return nil }
    let location = convert(point, from: superview)
    guard bounds.contains(location) else { return nil }
    for view in subviews.reversed() {
      if let target = view.hitTest(location) { return target }
    }
    return nil
  }
  static func install(in scroll: NSScrollView) {
    guard !(scroll.contentView is MusicTableClipView) else { return }
    let original = scroll.contentView
    let document = scroll.documentView
    let clip = MusicTableClipView(frame: original.frame)
    clip.drawsBackground = original.drawsBackground
    clip.backgroundColor = original.backgroundColor
    clip.autoresizingMask = original.autoresizingMask
    clip.automaticallyAdjustsContentInsets = original.automaticallyAdjustsContentInsets
    clip.contentInsets = original.contentInsets
    clip.postsBoundsChangedNotifications = original.postsBoundsChangedNotifications
    let origin = original.bounds.origin
    scroll.contentView = clip
    scroll.documentView = document
    clip.scroll(to: origin)
    scroll.reflectScrolledClipView(clip)
  }
}
