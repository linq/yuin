import AppKit
import SwiftUI

/// Preserve a native scroll view's visible row when toolbar/sidebar navigation relays out hidden pages.
struct ScrollPositionMemory: NSViewRepresentable {
  let active: Bool
  var table = false
  var scope: NativeScrollScope? = nil
  var rowIDs: [String] = []
  var contentCount = 0
  var loadMore: (() -> Void)?
  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ view: AnchorView, context: Context) {
    view.scope = scope
    view.requiresTable = table
    view.setActive(active)
    view.updateContent(rowIDs: rowIDs, count: contentCount, loadMore: loadMore)
    view.refreshAppearance()
  }
  static func dismantleNSView(_ view: AnchorView, coordinator: ()) { view.detach() }

  final class AnchorView: NSView {
    var scope: NativeScrollScope?
    var requiresTable = false
    private weak var scrollView: NSScrollView?
    private var observer: NSObjectProtocol?
    private var active = true
    private var restoring = false
    private var point: NSPoint?
    private var row: Int?
    private var rowID: String?
    private var rowIDs: [String] = []
    private var contentCount = 0
    private var loadMore: (() -> Void)?
    private var requestedCount: Int?
    private var requestScheduled = false
    private var rowInset: CGFloat = 0
    private var revision = 0

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil {
        detach()
      } else {
        DispatchQueue.main.async { [weak self] in self?.attach() }
      }
    }
    override func layout() {
      super.layout()
      attach()
    }
    func setActive(_ value: Bool) {
      guard value != active else { return }
      if !value { capture() }
      active = value
      restoring = false
      revision += 1
      if value { restoreAfterLayout(revision) }
    }
    func updateContent(rowIDs newIDs: [String], count: Int, loadMore: (() -> Void)?) {
      self.loadMore = loadMore
      guard newIDs != rowIDs || count != contentCount else { return }
      let newSet = Set(newIDs)
      let appended =
        count > contentCount && !rowIDs.isEmpty
        && rowIDs.allSatisfy { newSet.contains($0) }
      rowIDs = newIDs
      contentCount = count
      if appended && active {
        // Use the last observed position, before NSTableView lays out the new rows.
        // An ID anchor also survives inserting newly loaded songs into a sorted table.
        revision += 1
        restoreAfterLayout(revision)
      } else if active {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.active, !self.restoring else { return }
          self.capture()
        }
      }
    }
    func refreshAppearance() {
      DispatchQueue.main.async { [weak self] in self?.attach() }
    }
    private func attach() {
      if let scrollView {
        MusicScroller.apply(to: scrollView)
        return
      }
      guard window != nil else { return }
      var ancestor = superview
      while let parent = ancestor {
        if let scroll = findScrollView(in: parent) {
          scrollView = scroll
          MusicScroller.apply(to: scroll)
          scroll.contentView.postsBoundsChangedNotifications = true
          observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
          ) { [weak self] _ in
            guard let self, self.active, !self.restoring else { return }
            MusicScroller.apply(to: scroll)
            self.capture()
            self.scheduleNextPageIfNeeded()
          }
          if active { capture() }
          return
        }
        ancestor = parent.superview
      }
    }
    private func findScrollView(in view: NSView) -> NSScrollView? {
      if let scope { return scope.resolve(table: requiresTable) }
      var candidates: [(NSScrollView, CGFloat)] = []
      func containsTable(_ node: NSView?) -> Bool {
        guard let node else { return false }
        if node is NSTableView { return true }
        return node.subviews.contains { containsTable($0) }
      }
      func visit(_ node: NSView) {
        if let scroll = node as? NSScrollView,
          containsTable(scroll.documentView) == requiresTable
        {
          let rect = scroll.convert(scroll.bounds, to: self)
          if rect.contains(NSPoint(x: bounds.midX, y: bounds.midY)) {
            candidates.append(
              (scroll, abs(rect.width - bounds.width) + abs(rect.height - bounds.height)))
          }
        }
        for child in node.subviews where child !== self { visit(child) }
      }
      visit(view)
      return candidates.min { $0.1 < $1.1 }?.0
    }
    private func capture() {
      guard let scroll = scrollView else { return }
      point = scroll.contentView.bounds.origin
      row = nil
      rowID = nil
      if let table = scroll.documentView as? NSTableView, let point {
        let index = table.row(at: NSPoint(x: 1, y: point.y))
        if index >= 0 {
          row = index
          if rowIDs.indices.contains(index) { rowID = rowIDs[index] }
          rowInset = point.y - table.rect(ofRow: index).minY
        }
      }
    }
    private func restoreAfterLayout(_ token: Int) {
      restoring = true
      // Two run-loop turns allow both the toolbar and the native table to settle.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.active, self.revision == token else { return }
        self.restore()
        DispatchQueue.main.async { [weak self] in
          guard let self, self.active, self.revision == token else { return }
          self.restore()
          self.restoring = false
          self.capture()
        }
      }
    }
    private func restore() {
      guard let scroll = scrollView, var target = point else { return }
      scroll.layoutSubtreeIfNeeded()
      let anchorRow = rowID.flatMap { rowIDs.firstIndex(of: $0) } ?? row
      if let anchorRow, let table = scroll.documentView as? NSTableView,
        anchorRow < table.numberOfRows
      {
        target.y = table.rect(ofRow: anchorRow).minY + rowInset
      }
      scroll.contentView.scroll(to: target)
      scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func scheduleNextPageIfNeeded() {
      guard active, !restoring, loadMore != nil, requestedCount != contentCount,
        !requestScheduled, nearEnd
      else { return }
      requestScheduled = true
      // NSTableView can revise estimated row heights before the next run loop.
      // Keep the observed end-of-list intent even if its document grows meanwhile.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.requestScheduled = false
        guard self.active, !self.restoring, self.requestedCount != self.contentCount,
          let loadMore = self.loadMore
        else { return }
        self.requestedCount = self.contentCount
        loadMore()
      }
    }
    private var nearEnd: Bool {
      guard let scroll = scrollView, let document = scroll.documentView else { return false }
      let visible = scroll.contentView.bounds
      // Do not prefetch just because a short/filtered list fits in the viewport.
      return visible.minY > 0 && visible.height > 0
        && document.bounds.height - visible.maxY <= 64
    }
    func detach() {
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      scrollView = nil
      revision += 1
      restoring = false
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  }
}
