import AppKit
import SwiftUI

/// A supplementary header in the table's own clip view keeps one native scrollbar
/// and NSTableView's visible-row rendering, selection and accessibility.
struct CollectionScrollHeader: NSViewRepresentable {
  let content: AnyView
  let active: Bool
  let scope: NativeScrollScope
  var collapsed: (Bool) -> Void = { _ in }

  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.scope = scope
    view.content = content
    view.contentDirty = true
    view.active = active
    view.onCollapse = collapsed
    view.schedule()
  }
  static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.detach() }

  final class Anchor: NSView {
    var scope: NativeScrollScope?
    var content = AnyView(EmptyView())
    var contentDirty = true
    var active = true
    var onCollapse: (Bool) -> Void = { _ in }
    private weak var scroll: NSScrollView?
    private weak var table: NSTableView?
    private var hosting: NSHostingView<AnyView>?
    private var columns: NSTableHeaderView?
    private var originalHeader: NSTableHeaderView?
    private var originalInsets = NSEdgeInsetsZero
    private var originalAutomaticInsets = true
    private var observer: NSObjectProtocol?
    private var headerObserver: NSKeyValueObservation?
    private var scheduled = false
    private var inset: CGFloat = 0
    private var lastCollapsed: Bool?
    private let columnHeight: CGFloat = 24

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { detach() } else { schedule() }
    }
    override func layout() {
      super.layout()
      schedule()
    }
    func schedule() {
      guard !scheduled else { return }
      scheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.scheduled = false
        self.configure()
      }
    }
    private func configure() {
      guard window != nil else { return }
      if table == nil, let scroll = scope?.resolve(table: true),
        let table = scroll.documentView as? NSTableView
      {
        attach(table, scroll: scroll)
      }
      guard let table, let scroll, let hosting, let columns else { return }
      // SwiftUI may recreate the ordinary column header after a data update.
      // Its replacement below scrolls after the artwork, then pins to the viewport.
      if table.headerView != nil { table.headerView = nil }
      let width = max(1, scroll.contentView.bounds.width)
      if contentDirty || abs(hosting.frame.width - width) > 0.5 {
        hosting.rootView = AnyView(
          content.frame(width: width).fixedSize(horizontal: false, vertical: true))
        hosting.setFrameSize(NSSize(width: width, height: max(1, hosting.frame.height)))
        contentDirty = false
      }
      let height = ceil(hosting.fittingSize.height)
      let nextInset = height + columnHeight
      let oldOrigin = scroll.contentView.bounds.origin
      let firstLayout = inset == 0
      if abs(nextInset - inset) > 0.5 {
        let distance = oldOrigin.y + inset
        (scroll.contentView as? MusicTableClipView)?.headerHeight = nextInset
        hosting.frame = NSRect(x: 0, y: -nextInset, width: width, height: height)
        scroll.tile()
        let y = firstLayout ? -nextInset : oldOrigin.y < 0 ? distance - nextInset : oldOrigin.y
        inset = nextInset
        scroll.contentView.scroll(to: NSPoint(x: oldOrigin.x, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
      } else {
        hosting.frame = NSRect(x: 0, y: -inset, width: width, height: height)
      }
      columns.frame.size = NSSize(width: max(width, table.bounds.width), height: columnHeight)
      columns.needsDisplay = true
      positionHeader()
    }
    private func attach(_ table: NSTableView, scroll: NSScrollView) {
      self.table = table
      self.scroll = scroll
      originalHeader = table.headerView
      originalInsets = scroll.contentView.contentInsets
      originalAutomaticInsets = scroll.contentView.automaticallyAdjustsContentInsets
      scroll.contentView.automaticallyAdjustsContentInsets = false
      table.headerView = nil
      // Selection updates also reinstall SwiftUI's native header. Remove it in
      // the same update, before NSScrollView can tile around it for one frame.
      headerObserver = table.observe(\.headerView, options: [.new]) { table, _ in
        if table.headerView != nil { table.headerView = nil }
      }
      let hosting = NSHostingView(rootView: content)
      self.hosting = hosting
      scroll.contentView.addSubview(hosting, positioned: .above, relativeTo: table)
      let columns = TrackTableAppearance.supplementaryHeader(for: table)
      self.columns = columns
      scroll.contentView.addSubview(columns, positioned: .above, relativeTo: hosting)
      scroll.contentView.postsBoundsChangedNotifications = true
      observer = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
      ) { [weak self] _ in self?.positionHeader() }
    }
    private func positionHeader() {
      guard let scroll, let columns else { return }
      let y = scroll.contentView.bounds.minY
      columns.frame.origin = NSPoint(x: 0, y: max(-columnHeight, y))
      let value = y >= -columnHeight - 1
      guard active, lastCollapsed != value else { return }
      lastCollapsed = value
      DispatchQueue.main.async { [weak self] in
        guard let self, self.active, self.lastCollapsed == value else { return }
        self.onCollapse(value)
      }
    }
    func detach() {
      headerObserver = nil
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      hosting?.removeFromSuperview()
      columns?.removeFromSuperview()
      if let scroll {
        (scroll.contentView as? MusicTableClipView)?.headerHeight = 0
        scroll.contentView.contentInsets = originalInsets
        scroll.contentView.automaticallyAdjustsContentInsets = originalAutomaticInsets
      }
      if let table, table.headerView == nil { table.headerView = originalHeader }
      hosting = nil
      columns = nil
      table = nil
      scroll = nil
      inset = 0
      lastCollapsed = nil
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  }
}

struct CollectionGrid<Content: View>: View {
  @ViewBuilder let content: () -> Content
  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 20)],
      alignment: .leading, spacing: 26, content: content
    ).padding(.horizontal, 32)
  }
}
