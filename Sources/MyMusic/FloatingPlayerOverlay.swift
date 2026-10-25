import SwiftUI

struct FloatingPlayerOverlay: ViewModifier {
  static let scrollClearance: CGFloat = 84
  @EnvironmentObject private var model: AppModel
  func body(content: Content) -> some View {
    content.overlay(alignment: .bottom) {
      PlayerBar().padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 18)
        .opacity(model.showNowPlaying ? 0 : 1)
        .allowsHitTesting(!model.showNowPlaying)
        .accessibilityHidden(model.showNowPlaying)
    }
  }
}
