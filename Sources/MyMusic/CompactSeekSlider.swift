import AppKit
import MusicCore
import SwiftUI

struct CompactSeekSlider: View {
  @Environment(\.locale) private var locale
  var position: Double
  var duration: Double
  var enabled: Bool
  var seek: (Double) -> Void
  @State private var preview: SeekPreview?

  var body: some View {
    GeometryReader { geometry in
      NativeSeekSlider(
        position: position, duration: duration, enabled: enabled, seek: seek,
        preview: { preview = $0 }
      )
      .overlay(alignment: .topLeading) {
        if let preview, enabled {
          Text(Track.time(preview.seconds))
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .frame(width: 60, height: 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            .offset(x: min(max(0, preview.x - 30), max(0, geometry.size.width - 60)), y: -28)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
    }
  }
}

private struct SeekPreview {
  let seconds: Double
  let x: CGFloat
}

/// A thin track with native slider tracking, keyboard controls and accessibility.
private struct NativeSeekSlider: NSViewRepresentable {
  @Environment(\.locale) private var locale
  var position: Double
  var duration: Double
  var enabled: Bool
  var seek: (Double) -> Void
  var preview: (SeekPreview?) -> Void

  func makeNSView(context: Context) -> HoverSeekSlider {
    let slider = HoverSeekSlider()
    slider.cell = ThinSeekSliderCell()
    slider.isContinuous = true
    slider.controlSize = .mini
    slider.setAccessibilityLabel(L10n.text("播放进度"))
    slider.target = slider
    slider.action = #selector(HoverSeekSlider.commitSeek)
    return slider
  }

  func updateNSView(_ slider: HoverSeekSlider, context: Context) {
    slider.setAccessibilityLabel(L10n.text("播放进度"))
    let appearance: NSAppearance.Name = context.environment.colorScheme == .dark ? .darkAqua : .aqua
    if slider.appearance?.name != appearance { slider.appearance = NSAppearance(named: appearance) }
    slider.seek = seek
    slider.preview = preview
    slider.isEnabled = enabled
    // Playback time updates must not move the thumb underneath an active drag.
    guard !slider.isDragging else { return }
    slider.minValue = 0
    slider.maxValue = max(1, duration)
    slider.doubleValue = min(max(0, position), slider.maxValue)
    slider.setAccessibilityValueDescription("\(Track.time(position)) / \(Track.time(duration))")
    slider.needsDisplay = true
  }
}

private final class HoverSeekSlider: NSSlider {
  var seek: ((Double) -> Void)?
  var preview: ((SeekPreview?) -> Void)?
  private(set) var isDragging = false
  private(set) var isHovered = false
  private var hoverArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
    if let window {
      isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
    needsDisplay = true
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    preview(at: convert(event.locationInWindow, from: nil))
    needsDisplay = true
  }

  override func mouseMoved(with event: NSEvent) {
    preview(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    if !isDragging { preview?(nil) }
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    isDragging = true
    needsDisplay = true
    super.mouseDown(with: event)
    isDragging = false
    seek?(doubleValue)
    if let window {
      let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
      isHovered = bounds.contains(point)
      if isHovered { preview(at: point) } else { preview?(nil) }
    }
    needsDisplay = true
  }

  private func preview(at point: NSPoint) {
    guard isEnabled, let cell = cell as? ThinSeekSliderCell else {
      preview?(nil)
      return
    }
    let track = cell.trackRect(flipped: isFlipped)
    let fraction = min(1, max(0, (point.x - track.minX) / max(1, track.width)))
    preview?(
      SeekPreview(
        seconds: minValue + fraction * (maxValue - minValue),
        x: track.minX + fraction * track.width))
  }

  @objc func commitSeek() {
    if isDragging {
      // Native continuous tracking updates the preview, but seeks only on release.
      let x = (cell as? NSSliderCell)?.knobRect(flipped: isFlipped).midX ?? 0
      preview?(SeekPreview(seconds: doubleValue, x: x))
    } else {
      seek?(doubleValue)
    }
  }
}

private final class ThinSeekSliderCell: NSSliderCell {
  func trackRect(flipped: Bool) -> NSRect {
    thinTrack(in: barRect(flipped: flipped), flipped: flipped)
  }

  private func thinTrack(in rect: NSRect, flipped: Bool) -> NSRect {
    let knob = knobRect(flipped: flipped)
    return NSRect(
      x: rect.minX + knob.width / 2, y: rect.midY - 1,
      width: max(0, rect.width - knob.width), height: 2)
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let knob = knobRect(flipped: flipped)
    let track = thinTrack(in: rect, flipped: flipped)
    NSColor.labelColor.withAlphaComponent(isEnabled ? 0.16 : 0.08).setFill()
    NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
    let progress = NSRect(
      x: track.minX, y: track.minY,
      width: min(track.width, max(0, knob.midX - track.minX)), height: track.height)
    NSColor.secondaryLabelColor.setFill()
    NSBezierPath(roundedRect: progress, xRadius: 1, yRadius: 1).fill()
  }

  override func drawKnob(_ knobRect: NSRect) {
    guard let slider = controlView as? HoverSeekSlider,
      isEnabled && (slider.isHovered || slider.isDragging)
    else { return }
    NSColor.labelColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 3, y: knobRect.midY - 3, width: 6, height: 6))
      .fill()
  }
}
