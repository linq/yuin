import AppKit
import CoreImage
import SwiftUI

/// Retained pages register only their active scroll view. No scroll positions
/// are published into the SwiftUI browser or its song rows.
final class NavigationToolbarSource {
  weak var scroll: NSScrollView?
  weak var surface: NavigationToolbarBlurView?
  func select(_ scroll: NSScrollView) {
    self.scroll = scroll
    surface?.attach(scroll)
  }
  func release(_ scroll: NSScrollView) {
    guard self.scroll === scroll else { return }
    self.scroll = nil
    surface?.attach(nil)
  }
}

private struct NavigationToolbarSourceKey: EnvironmentKey {
  static let defaultValue: NavigationToolbarSource? = nil
}
extension EnvironmentValues {
  var navigationToolbarSource: NavigationToolbarSource? {
    get { self[NavigationToolbarSourceKey.self] }
    set { self[NavigationToolbarSourceKey.self] = newValue }
  }
}

struct NavigationToolbarScrollSource: NSViewRepresentable {
  @Environment(\.navigationToolbarSource) private var source
  let scope: NativeScrollScope
  let active: Bool
  var table = false
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.source = source
    view.scope = scope
    view.active = active
    view.table = table
    view.schedule()
  }
  static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.detach() }
  final class Anchor: NSView {
    weak var source: NavigationToolbarSource?
    var scope: NativeScrollScope?
    var active = false
    var table = false
    private weak var scroll: NSScrollView?
    private var scheduled = false
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
        guard self.window != nil, self.active else {
          self.detach()
          return
        }
        guard let scroll = self.scope?.resolve(table: self.table) else { return }
        self.scroll = scroll
        self.source?.select(scroll)
      }
    }
    func detach() {
      if let scroll { source?.release(scroll) }
      scroll = nil
    }
  }
}

struct NavigationToolbarSurface: NSViewRepresentable {
  let source: NavigationToolbarSource
  func makeNSView(context: Context) -> NavigationToolbarBlurView {
    let view = NavigationToolbarBlurView()
    source.surface = view
    view.attach(source.scroll)
    return view
  }
  func updateNSView(_ view: NavigationToolbarBlurView, context: Context) {
    source.surface = view
    view.attach(source.scroll)
  }
  static func dismantleNSView(_ view: NavigationToolbarBlurView, coordinator: ()) {
    view.attach(nil)
  }
}

/// A content-colored base is independent of desktop tint. Only the document
/// slice passing beneath the toolbar contributes to the translucent color.
final class NavigationToolbarBlurView: NSView {
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private weak var scroll: NSScrollView?
  private var observers: [NSObjectProtocol] = []
  private var pending: DispatchWorkItem?
  private var lastCapture = 0.0
  private var capturedRect: NSRect?
  private var image: NSImage?
  private(set) var captureCount = 0
  override var isFlipped: Bool { true }
  private var baseColor: NSColor {
    var color = NSColor.white
    effectiveAppearance.performAsCurrentDrawingAppearance {
      color = MusicSurface.content.usingColorSpace(.sRGB) ?? .white
    }
    return color
  }
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    identifier = NSUserInterfaceItemIdentifier("MyMusic.navigationToolbarBackdrop")
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func attach(_ scroll: NSScrollView?) {
    guard self.scroll !== scroll else { return }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    pending?.cancel()
    pending = nil
    self.scroll = scroll
    image = nil
    capturedRect = nil
    needsDisplay = true
    if let scroll {
      for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        observers.append(
          NotificationCenter.default.addObserver(
            forName: name, object: scroll.contentView, queue: .main
          ) { [weak self] _ in self?.schedule() })
      }
      schedule()
    }
  }
  override func layout() {
    super.layout()
    schedule()
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    schedule()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    image = nil
    capturedRect = nil
    needsDisplay = true
    schedule()
  }
  private func schedule() {
    guard pending == nil, window != nil, let scroll, bounds.width > 0, bounds.height > 0 else {
      return
    }
    let rect = scroll.contentView.convert(bounds, from: self)
    guard rect != capturedRect else { return }
    let work = DispatchWorkItem { [weak self] in
      self?.pending = nil
      self?.capture()
    }
    pending = work
    let delay = max(0, 1.0 / 30 - (ProcessInfo.processInfo.systemUptime - lastCapture))
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }
  private func capture() {
    guard let scroll, let document = scroll.documentView, window != nil,
      bounds.width > 0, bounds.height > 0
    else { return }
    let clip = scroll.contentView
    let rect = clip.convert(bounds, from: self)
    capturedRect = rect
    lastCapture = ProcessInfo.processInfo.systemUptime
    image = nil
    needsDisplay = true
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
    // Render only a narrow document strip, including the supplementary artwork
    // header hosted beside NSTableView. Column headers and scrollers stay out.
    let size = bounds.size
    let base = baseColor
    let composite = NSImage(size: size, flipped: true) { target in
      base.setFill()
      target.fill()
      let sources =
        [document]
        + clip.subviews.filter {
          $0 !== document && !($0 is NSTableHeaderView) && !($0 is NSScroller)
        }
      for view in sources where !view.isHidden {
        let requested = view.convert(rect, from: clip)
        let visible = requested.intersection(view.bounds)
        guard !visible.isEmpty, let bitmap = view.bitmapImageRepForCachingDisplay(in: visible)
        else { continue }
        view.cacheDisplay(in: visible, to: bitmap)
        let rendered = NSImage(size: visible.size)
        rendered.addRepresentation(bitmap)
        let position = clip.convert(visible, from: view)
        rendered.draw(
          in: NSRect(
            x: position.minX - rect.minX, y: position.minY - rect.minY,
            width: position.width, height: position.height),
          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      }
      return true
    }
    guard let bitmap = composite.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return
    }
    let scale = min(1, 200 / CGFloat(bitmap.width))
    let input = CIImage(cgImage: bitmap).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blur = input.clampedToExtent().applyingFilter(
      "CIGaussianBlur", parameters: [kCIInputRadiusKey: 6])
    if let output = Self.context.createCGImage(blur, from: input.extent) {
      image = NSImage(cgImage: output, size: size)
      captureCount += 1
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    baseColor.setFill()
    bounds.fill()
    image?.draw(
      in: bounds, from: .zero, operation: .sourceOver, fraction: 0.30,
      respectFlipped: true, hints: nil)
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  deinit {
    pending?.cancel()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
}
