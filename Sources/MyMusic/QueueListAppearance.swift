import AppKit
import SwiftUI

/// Native List keeps queue reordering and keyboard behavior. Its scroll surface
/// must blend into the album backdrop when embedded in the full-window player.
struct QueueListAppearance: NSViewRepresentable {
  let player: Bool
  var scope: NativeScrollScope? = nil
  var headerReference: QueueHeaderReference? = nil
  var headerHeight: CGFloat = QueueHeaderLayout.height
  var entryIDs: [UUID] = []
  var active = true
  var jumpRequest = 0
  var browsingChanged: (Bool) -> Void = { _ in }
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.player = player
    view.scope = scope
    view.headerReference = headerReference
    view.headerHeight = headerHeight
    view.active = active
    view.browsingChanged = browsingChanged
    view.update(entries: entryIDs, jumpRequest: jumpRequest)
    view.needsLayout = true
  }
  static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.detach() }
  final class Anchor: NSView {
    var player = false
    var scope: NativeScrollScope?
    var headerReference: QueueHeaderReference?
    var headerHeight: CGFloat = QueueHeaderLayout.height
    var active = true
    var browsingChanged: (Bool) -> Void = { _ in }
    private weak var scroll: NSScrollView?
    private weak var table: NSTableView?
    private var headerBackdrop: QueueHeaderBackdrop?
    private var updatingHeader = false
    private var observer: NSObjectProtocol?
    private var ids: [String] = []
    private var anchorID: String?
    private var rowInset: CGFloat = 0
    private var origin = NSPoint.zero
    private var browsing = false
    private var restoring = false
    private var jumpRequest = 0
    private var revision = 0

    func update(entries: [UUID], jumpRequest: Int) {
      let next = (player ? ["queue-start"] : []) + entries.map(\.uuidString)
      let changed = next != ids
      ids = next
      if self.jumpRequest != jumpRequest {
        self.jumpRequest = jumpRequest
        origin = scroll.map { startOrigin(in: $0) } ?? .zero
        anchorID = nil
        restoreAfterLayout()
      } else if changed, scroll != nil {
        restoreAfterLayout()
      }
    }
    private func capture() {
      guard !updatingHeader else { return }
      positionHeaderBackdrop()
      guard active, !restoring, let scroll else { return }
      origin = scroll.contentView.bounds.origin
      if let table {
        let row = table.row(at: NSPoint(x: 1, y: origin.y))
        if ids.indices.contains(row) {
          anchorID = ids[row]
          rowInset = origin.y - table.rect(ofRow: row).minY
        } else {
          anchorID = nil
        }
      }
      let next = origin.y - startOrigin(in: scroll).y > 60
      if browsing != next {
        browsing = next
        DispatchQueue.main.async { [weak self] in self?.browsingChanged(next) }
      }
    }
    private func positionHeaderBackdrop() {
      guard !updatingHeader, let scroll, let clip = scroll.contentView as? MusicTableClipView else {
        return
      }
      updatingHeader = true
      defer { updatingHeader = false }
      let height: CGFloat = player ? 0 : headerHeight
      let firstLayout = clip.headerHeight != height
      let origin = clip.bounds.origin
      let wasAtStart = origin.y <= 1
      // Keep header space in the document range, so its source is an ordinary
      // table region rather than a separate AppKit content inset.
      scroll.automaticallyAdjustsContentInsets = false
      clip.automaticallyAdjustsContentInsets = false
      if scroll.contentInsets.top != 0 { scroll.contentInsets.top = 0 }
      if clip.contentInsets.top != 0 { clip.contentInsets.top = 0 }
      if firstLayout {
        clip.headerHeight = height
        scroll.tile()
        if wasAtStart {
          clip.scroll(to: NSPoint(x: origin.x, y: -height))
          scroll.reflectScrolledClipView(clip)
        }
      }
      guard !player else {
        headerBackdrop?.removeFromSuperview()
        headerBackdrop = nil
        return
      }
      let backdrop = headerBackdrop ?? QueueHeaderBackdrop(frame: .zero)
      headerBackdrop = backdrop
      if backdrop.superview !== clip {
        clip.addSubview(backdrop, positioned: .above, relativeTo: table)
      }
      var rect =
        headerReference?.view.map { clip.convert($0.bounds, from: $0) }
        ?? NSRect(
          x: clip.bounds.minX, y: clip.bounds.minY, width: clip.bounds.width, height: height)
      rect.size.width = min(rect.width, clip.bounds.width)
      backdrop.frame = rect
      if active, let table {
        backdrop.update(table: table, rect: table.convert(rect, from: clip), revision: revision)
      }
    }
    private func startOrigin(in scroll: NSScrollView) -> NSPoint {
      var proposed = scroll.contentView.bounds
      // The header occupies a negative document range. Zero would leave
      // the first song underneath the material instead of below the controls.
      proposed.origin = NSPoint(
        x: 0, y: scroll.contentView.documentRect.minY - max(1024, proposed.height))
      return scroll.contentView.constrainBoundsRect(proposed).origin
    }
    private func restoreAfterLayout() {
      revision += 1
      let token = revision
      restoring = true
      func restore() {
        guard let scroll else { return }
        scroll.layoutSubtreeIfNeeded()
        var point = origin
        if browsing, let anchorID, let index = ids.firstIndex(of: anchorID), let table,
          index < table.numberOfRows
        {
          point.y = table.rect(ofRow: index).minY + rowInset
        }
        scroll.contentView.scroll(to: point)
        scroll.reflectScrolledClipView(scroll.contentView)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.revision == token else { return }
        restore()
        DispatchQueue.main.async { [weak self] in
          guard let self, self.revision == token else { return }
          restore()
          self.restoring = false
          self.capture()
        }
      }
    }
    private func attach(_ scroll: NSScrollView) {
      guard self.scroll !== scroll else { return }
      detach()
      self.scroll = scroll
      func findTable(_ node: NSView) -> NSTableView? {
        if let table = node as? NSTableView { return table }
        return node.subviews.lazy.compactMap(findTable).first
      }
      table = scroll.documentView.flatMap(findTable)
      // Let AppKit show a real insertion gap while retaining native List reordering.
      table?.draggingDestinationFeedbackStyle = .gap
      scroll.contentView.postsBoundsChangedNotifications = true
      observer = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
      ) { [weak self] _ in self?.capture() }
      capture()
    }
    func detach() {
      headerBackdrop?.detach()
      headerBackdrop?.removeFromSuperview()
      headerBackdrop = nil
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      scroll = nil
      table = nil
      revision += 1
      restoring = false
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

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
        if let scroll = scope?.resolve(table: true) ?? (scope == nil ? find(node) : nil) {
          attach(scroll)
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
          positionHeaderBackdrop()
          return
        }
        parent = node.superview
      }
    }
  }
}
