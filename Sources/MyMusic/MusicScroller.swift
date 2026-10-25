import AppKit

/// Keeps AppKit's scrolling, tracking and accessibility, with an inset capsule track.
final class MusicScroller: NSScroller {
  var blendsWithBackdrop = false
  override var isOpaque: Bool { blendsWithBackdrop ? false : super.isOpaque }
  override class var isCompatibleWithOverlayScrollers: Bool { true }

  static func applyTree(to root: NSView) {
    if let scroll = root as? NSScrollView { apply(to: scroll) }
    for child in root.subviews { applyTree(to: child) }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  static func apply(to scroll: NSScrollView) {
    // The full-window lyric presentation follows Apple Music's edge fades rather
    // than a persistent gutter, even when the system prefers legacy scrollbars.
    if scroll.identifier?.rawValue == "MyMusic.synchronizedLyrics" {
      if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
      return
    }
    // SwiftUI tables can choose a different mode from ordinary ScrollViews.
    // Use the same system preference for every rail and remove native gutter borders.
    if scroll.scrollerStyle != NSScroller.preferredScrollerStyle {
      scroll.scrollerStyle = NSScroller.preferredScrollerStyle
    }
    if scroll.borderType != .noBorder { scroll.borderType = .noBorder }
    let blended = ["MyMusic.playerQueue", "MyMusic.sidebarQueue"].contains(
      scroll.identifier?.rawValue ?? "")
    guard let original = scroll.verticalScroller else { return }
    if let existing = original as? MusicScroller {
      existing.blendsWithBackdrop = blended
      return
    }
    let replacement = MusicScroller(frame: original.frame)
    replacement.blendsWithBackdrop = blended
    replacement.controlSize = original.controlSize
    replacement.scrollerStyle = original.scrollerStyle
    replacement.knobStyle = original.knobStyle
    replacement.target = original.target
    replacement.action = original.action
    replacement.isEnabled = original.isEnabled
    replacement.doubleValue = original.doubleValue
    replacement.knobProportion = original.knobProportion
    scroll.verticalScroller = replacement
  }

  override func draw(_ dirtyRect: NSRect) {
    if scrollerStyle == .overlay {
      // AppKit manages fading the knob and slot independently in overlay mode.
      super.draw(dirtyRect)
    } else {
      if !blendsWithBackdrop {
        MusicSurface.content.setFill()
        bounds.fill()
      }
      drawKnobSlot(in: rect(for: .knobSlot), highlight: false)
      if isEnabled { drawKnob() }
    }
  }

  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
    let slot = capsuleRect(slotRect)
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    NSColor.labelColor.withAlphaComponent(dark ? 0.055 : 0.035).setFill()
    NSBezierPath(roundedRect: slot, xRadius: slot.width / 2, yRadius: slot.width / 2).fill()
  }

  override func drawKnob() {
    let knob = capsuleRect(rect(for: .knob))
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    NSColor.labelColor.withAlphaComponent(hitPart == .knob ? 0.6 : dark ? 0.36 : 0.5).setFill()
    NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
  }

  private func capsuleRect(_ rect: NSRect) -> NSRect {
    // Use the same horizontal inset for thumb and track, including short thumbs.
    NSRect(x: bounds.midX - 4.5, y: rect.minY + 2, width: 9, height: max(0, rect.height - 4))
  }
}
