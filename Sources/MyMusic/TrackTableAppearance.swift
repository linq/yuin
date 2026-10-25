import AppKit
import MusicCore
import SwiftUI

/// Keep the native table's selection, keyboard navigation and accessibility while adapting its columns.
struct TrackTableAppearance: NSViewRepresentable {
  @Environment(\.locale) private var locale
  // Reapply decoration after SwiftUI rebuilds the selected row's hosted cells.
  var selection: Set<String> = []
  var scope: NativeScrollScope? = nil
  var density: TrackListDensity = .standard
  private static let columnNames: [MusicLocalizedText] = ["歌曲", "艺人", "专辑", "时长"]
  static let selectionColor = MusicAccent.native

  static func supplementaryHeader(for table: NSTableView) -> NSTableHeaderView {
    let header = QuietHeaderView(frame: NSRect(x: 0, y: 0, width: table.bounds.width, height: 24))
    header.tableView = table
    return header
  }

  static func updateSelection(in table: NSTableView) {
    if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
    guard let clip = table.enclosingScrollView?.contentView else { return }
    let existing = clip.subviews.compactMap { $0 as? SelectionBackground }.first {
      $0.table === table
    }
    let background = existing ?? SelectionBackground(frame: clip.bounds)
    background.table = table
    if background.superview == nil {
      clip.addSubview(background, positioned: .below, relativeTo: table)
    }
    background.frame = clip.bounds
    background.needsDisplay = true
    decorateRows(in: table)
  }
  private static func decorateRows(in table: NSTableView) {
    table.enumerateAvailableRowViews { row, index in
      let color: NSColor = table.selectedRowIndexes.contains(index) ? selectionColor : .clear
      if row.backgroundColor != color { row.backgroundColor = color }
    }
  }
  /// A clip-view sibling survives SwiftUI's reconstruction of selected row views.
  /// Drawing only the viewport avoids a tall backing surface for large playlists.
  private final class SelectionBackground: NSView {
    weak var table: NSTableView?
    override var allowsVibrancy: Bool { false }
    override var isFlipped: Bool { true }
    override func viewWillDraw() {
      if let table { TrackTableAppearance.decorateRows(in: table) }
      super.viewWillDraw()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
      guard let table else { return }
      TrackTableAppearance.selectionColor.setFill()
      for index in table.selectedRowIndexes where index < table.numberOfRows {
        let rect = convert(table.rect(ofRow: index), from: table).insetBy(dx: 1, dy: 0)
        if rect.intersects(dirtyRect) {
          NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
      }
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
    view.density = density
    view.needsLayout = true
  }
  final class Anchor: NSView {
    var scope: NativeScrollScope?
    var density = TrackListDensity.standard
    private weak var table: NSTableView?
    private var scheduled = false
    private var lastWidth: CGFloat = 0
    private var selectionObserver: NSObjectProtocol?
    private var rowHeightObserver: NSKeyValueObservation?
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
      // SwiftUI can reset rowHeight after a data/filter reload without laying
      // out this background adapter again. Keep the chosen density authoritative.
      if rowHeightObserver == nil {
        rowHeightObserver = table.observe(\.rowHeight, options: [.new]) { [weak self] table, _ in
          guard let self else { return }
          self.applyDensity(to: table)
        }
      }
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
      applyDensity(to: table)
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
    private func applyDensity(to table: NSTableView) {
      if table.usesAutomaticRowHeights { table.usesAutomaticRowHeights = false }
      if abs(table.rowHeight - density.rowHeight) > 0.5 { table.rowHeight = density.rowHeight }
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
