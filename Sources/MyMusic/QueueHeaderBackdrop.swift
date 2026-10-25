import AppKit
import CoreImage
import SwiftUI

enum QueueHeaderLayout { static let height: CGFloat = 92 }
final class QueueHeaderReference { weak var view: NSView? }
struct QueueHeaderAnchor: NSViewRepresentable {
  let reference: QueueHeaderReference
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    reference.view = view
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}

/// Native List may omit inset-covered row layers from WindowServer composition.
/// Sample only this small native table region and blur it, keeping the actual
/// passing artwork visible when the system material cannot sample hosted rows.
final class QueueHeaderBackdrop: NSVisualEffectView {
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private let imageView = NSImageView()
  private weak var table: NSTableView?
  private var sourceRect = NSRect.zero
  private var capturedRect: NSRect?
  private var requestedRevision = 0
  private var capturedRevision = -1
  private var pending: DispatchWorkItem?
  private var lastCapture = 0.0
  private(set) var captureCount = 0
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }
  private func configure() {
    material = .headerView
    blendingMode = .withinWindow
    state = .active
    identifier = NSUserInterfaceItemIdentifier("MyMusic.queueHeaderBackdrop")
    setAccessibilityElement(false)
    imageView.setAccessibilityElement(false)
    imageView.imageScaling = .scaleAxesIndependently
    imageView.alphaValue = 0.72
    imageView.autoresizingMask = [.width, .height]
    addSubview(imageView)
  }
  override func layout() {
    super.layout()
    imageView.frame = bounds
  }
  func update(table: NSTableView, rect: NSRect, revision: Int = 0) {
    let replaced = self.table !== table
    self.table = table
    sourceRect = rect
    requestedRevision = revision
    guard replaced || capturedRect != rect || capturedRevision != revision else { return }
    guard pending == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pending = nil
      self.capture()
    }
    pending = work
    let delay = max(0, 1.0 / 30 - (ProcessInfo.processInfo.systemUptime - lastCapture))
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }
  private func capture() {
    guard let table, window != nil, sourceRect.width > 0, sourceRect.height > 0 else { return }
    lastCapture = ProcessInfo.processInfo.systemUptime
    capturedRect = sourceRect
    capturedRevision = requestedRevision
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
      imageView.image = nil
      return
    }
    guard let bitmap = table.bitmapImageRepForCachingDisplay(in: sourceRect) else { return }
    table.cacheDisplay(in: sourceRect, to: bitmap)
    guard let source = bitmap.cgImage else { return }
    let scale = min(1, 160 / CGFloat(source.width))
    let input = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blurred = input.clampedToExtent().applyingFilter(
      "CIGaussianBlur", parameters: [kCIInputRadiusKey: 8])
    guard let result = Self.context.createCGImage(blurred, from: input.extent) else { return }
    imageView.image = NSImage(cgImage: result, size: bounds.size)
    captureCount += 1
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    capturedRect = nil
    if let table { update(table: table, rect: sourceRect, revision: requestedRevision) }
  }
  func detach() {
    pending?.cancel()
    pending = nil
    table = nil
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  deinit { pending?.cancel() }
}
