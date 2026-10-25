import AppKit
import SwiftUI

enum MusicAccent {
  static let native = NSColor(srgbRed: 0.98, green: 0.14, blue: 0.23, alpha: 1)
  static let color = Color(nsColor: native)
}

struct MusicCollectionActionStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var enabled
  @Environment(\.isFocused) private var focused
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovered = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, 16).frame(minWidth: 80, minHeight: 34)
      .foregroundStyle(prominent ? Color.white : MusicAccent.color)
      .background {
        Capsule().fill(
          prominent ? MusicAccent.color : Color.primary.opacity(hovered ? 0.10 : 0.055))
      }
      .overlay {
        Capsule().fill(
          Color.black.opacity(configuration.isPressed ? 0.12 : hovered && prominent ? 0.06 : 0)
        )
        .allowsHitTesting(false)
        Capsule().strokeBorder(MusicAccent.color.opacity(focused ? 0.7 : 0), lineWidth: 3)
          .padding(-3).allowsHitTesting(false)
      }
      .opacity(enabled ? 1 : 0.38)
      .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
      .contentShape(Capsule()).onHover { hovered = $0 && enabled }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
