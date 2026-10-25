import AppKit
import MusicCore
import SwiftUI

/// Keep the native table's selection, keyboard navigation and accessibility while adapting its columns.
struct TrackTableAppearance: NSViewRepresentable {
  @Environment(\.locale) private var locale
  // Reapply decoration after SwiftUI rebuilds the selected row's hosted cells.
  var selection: Set<String> = []
  var scope: NativeScrollScope? = nil
  private static let columnNames: [MusicLocalizedText] = ["歌曲", "艺人", "专辑", "时长"]
  static let selectionColor = NSColor(srgbRed: 0.98, green: 0.14, blue: 0.23, alpha: 1)

  static func supplementaryHeader(for table: NSTableView) -> NSTableHeaderView {
    let header = QuietHeaderView(frame: NSRect(x: 0, y: 0, width: table.bounds.width, height: 24))
    header.tableView = table
    return header
  }

  static func updateSelection(in table: NSTableView) {
    if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
    func update(_ row: NSTableRowView, _ index: Int) {
      let existing = row.subviews.first { $0 is SelectionBackground } as? SelectionBackground
      guard table.selectedRowIndexes.contains(index) else {
        existing?.isHidden = true
        return
      }
      let background = existing ?? SelectionBackground(frame: row.bounds)
      if background.superview == nil {
        background.autoresizingMask = [.width, .height]
        row.addSubview(background, positioned: .below, relativeTo: row.subviews.first)
      }
      background.frame = row.bounds
      background.isHidden = false
    }
    table.enumerateAvailableRowViews { row, index in update(row, index) }
    // Changing the native highlight style may recreate its visible row views.
    let visible = table.rows(in: table.visibleRect)
    if visible.location != NSNotFound {
      let indexes = IndexSet(integersIn: visible.location..<NSMaxRange(visible))
      for index in table.selectedRowIndexes.intersection(indexes) {
        if let row = table.rowView(atRow: index, makeIfNecessary: true) { update(row, index) }
      }
    }
  }
  private final class SelectionBackground: NSView {
    override var allowsVibrancy: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
      TrackTableAppearance.selectionColor.setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0), xRadius: 5, yRadius: 5).fill()
    }
  }

  // SwiftUI retains native columns along with scroll position, but does not always
  // update their titles after a locale change. Update the existing columns in place.
  static func localizeColumns(in table: NSTableView, language: MusicLanguage = .selected()) {
    for column in table.tableColumns {
      guard
        let name = columnNames.first(where: {
          column.title == L10n.text($0, language: .english)
            || column.title == L10n.text($0, language: .simplifiedChinese)
        })
      else { continue }
      let title = L10n.text(name, language: language)
      if column.title != title {
        column.title = title
        table.headerView?.needsDisplay = true
      }
    }
  }
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.scope = scope
    view.needsLayout = true
  }
  final class Anchor: NSView {
    var scope: NativeScrollScope?
    private weak var table: NSTableView?
    private var scheduled = false
    private var lastWidth: CGFloat = 0
    private var selectionObserver: NSObjectProtocol?
    private var scrollObserver: NSObjectProtocol?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.configure() }
    }
    override func layout() {
      super.layout()
      // SwiftUI also writes column widths during layout; apply our sizing after it settles.
      guard !scheduled else { return }
      scheduled = true
      DispatchQueue.main.async { [weak self] in
        self?.scheduled = false
        self?.configure()
      }
    }
    private func configure() {
      if table == nil {
        func find(_ view: NSView) -> NSTableView? {
          if let table = view as? NSTableView,
            table.tableColumns.contains(where: {
              $0.title == L10n.text("专辑", language: .english)
                || $0.title == L10n.text("专辑", language: .simplifiedChinese)
            })
          {
            return table
          }
          for child in view.subviews where child !== self {
            if let table = find(child) { return table }
          }
          return nil
        }
        if let scope {
          table = scope.resolve(table: true)?.documentView as? NSTableView
        } else {
          var ancestor = superview
          while let parent = ancestor {
            if let found = find(parent) {
              table = found
              break
            }
            ancestor = parent.superview
          }
        }
      }
      guard let table, let scroll = table.enclosingScrollView else { return }
      if selectionObserver == nil {
        selectionObserver = NotificationCenter.default.addObserver(
          forName: NSTableView.selectionDidChangeNotification, object: table, queue: .main
        ) { [weak table] _ in
          if let table { TrackTableAppearance.updateSelection(in: table) }
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
          forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak table] _ in
          if let table { TrackTableAppearance.updateSelection(in: table) }
        }
      }
      TrackTableAppearance.updateSelection(in: table)
      TrackTableAppearance.localizeColumns(in: table)
      MusicScroller.apply(to: scroll)
      if table.usesAlternatingRowBackgroundColors {
        table.usesAlternatingRowBackgroundColors = false
      }
      if !table.gridStyleMask.isEmpty { table.gridStyleMask = [] }
      if table.backgroundColor != .clear { table.backgroundColor = .clear }
      if scroll.drawsBackground { scroll.drawsBackground = false }
      if let header = table.headerView, !(header is QuietHeaderView) {
        table.headerView = QuietHeaderView(frame: header.frame)
      }
      for column in table.tableColumns where !(column.headerCell is QuietHeaderCell) {
        column.headerCell = QuietHeaderCell(textCell: column.title)
      }
      let width = bounds.width - (scroll.hasVerticalScroller ? 15 : 0)
      guard width > 200 else { return }
      let album = table.tableColumns.first { $0.title == L10n.text("专辑") }
      let duration = table.tableColumns.first { $0.title == L10n.text("时长") }
      if abs(width - lastWidth) < 1, album?.isHidden == (width < 700),
        duration?.isHidden == (width < 400)
      {
        return
      }
      lastWidth = width
      album?.isHidden = width < 700
      duration?.isHidden = width < 400
      let showAlbum = width >= 700
      // Native inset tables reserve padding for each visible column, in addition to cell widths.
      let available = max(190, width - (width < 400 ? 70 : showAlbum ? 180 : 125))
      for column in table.tableColumns {
        switch column.title {
        case L10n.text("歌曲"): column.width = available * (showAlbum ? 0.48 : 0.67)
        case L10n.text("艺人"): column.width = available * (showAlbum ? 0.24 : 0.33)
        case L10n.text("专辑"): column.width = available * 0.28
        default: break
        }
      }
      table.sizeToFit()
    }
    deinit {
      if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
      if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }
  }
  private final class QuietHeaderView: NSTableHeaderView {
    override var allowsVibrancy: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
      MusicSurface.content.setFill()
      bounds.fill()
      guard let tableView else { return }
      for (index, column) in tableView.tableColumns.enumerated() where !column.isHidden {
        column.headerCell.draw(withFrame: headerRect(ofColumn: index), in: self)
      }
    }
  }
  private final class QuietHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
      MusicSurface.content.setFill()
      cellFrame.fill()
      (stringValue as NSString).draw(
        in: cellFrame.insetBy(dx: 5, dy: 4),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 11, weight: .medium),
          .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
  }
}
