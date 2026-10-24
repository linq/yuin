import AppKit
import MusicCore

@MainActor enum WindowSizing {
  static func present() {
    guard let window = NSApp.keyWindow, window.attachedSheet == nil else { return }
    let alert = NSAlert()
    alert.messageText = L10n.text("调整窗口大小")
    alert.informativeText = L10n.text("输入包含标题栏的窗口宽、高（pt），方便对照其他应用。")
    alert.addButton(withTitle: L10n.text("应用"))
    alert.addButton(withTitle: L10n.text("取消"))

    func field(_ value: CGFloat, label: String) -> NSTextField {
      let field = NSTextField(string: String(Int(value.rounded())))
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.usesGroupingSeparator = false
      formatter.allowsFloats = false
      formatter.minimum = 1
      formatter.maximum = 10000
      field.formatter = formatter
      field.setAccessibilityLabel(label)
      field.widthAnchor.constraint(equalToConstant: 150).isActive = true
      return field
    }
    let width = field(window.frame.width, label: L10n.text("窗口宽度"))
    let height = field(window.frame.height, label: L10n.text("窗口高度"))
    let stack = NSStackView(views: [
      NSStackView(views: [NSTextField(labelWithString: L10n.text("宽度")), width]),
      NSStackView(views: [NSTextField(labelWithString: L10n.text("高度")), height]),
    ])
    stack.orientation = .vertical
    stack.spacing = 12
    stack.frame = NSRect(x: 0, y: 0, width: 230, height: 70)
    alert.accessoryView = stack
    alert.window.initialFirstResponder = width
    alert.beginSheetModal(for: window) { response in
      guard response == .alertFirstButtonReturn,
        let w = Double(width.stringValue), let h = Double(height.stringValue),
        w.isFinite, h.isFinite, w > 0, h > 0
      else { return }
      let screen = window.screen?.visibleFrame
      let size = NSSize(
        width: min(max(CGFloat(w), window.minSize.width), screen?.width ?? CGFloat(w)),
        height: min(max(CGFloat(h), window.minSize.height), screen?.height ?? CGFloat(h)))
      var frame = NSRect(
        x: window.frame.minX, y: window.frame.maxY - size.height,
        width: size.width, height: size.height)
      if let screen {
        frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - size.width)
        frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - size.height)
      }
      window.setFrame(frame, display: true)
    }
  }
}
