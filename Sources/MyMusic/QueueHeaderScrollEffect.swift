import SwiftUI

/// The fixed material header is a scroll inset, so songs pass behind it.
/// Let the system blend that boundary rather than overlaying fog on visible rows.
struct QueueHeaderScrollEffect: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      content
    }
  }
}
