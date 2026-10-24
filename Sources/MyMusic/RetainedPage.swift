import SwiftUI

private struct MusicPageActivityKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  var musicPageIsActive: Bool {
    get { self[MusicPageActivityKey.self] }
    set { self[MusicPageActivityKey.self] = newValue }
  }
}

/// Keep view identity and local state while making only the visible page interactive.
struct RetainedPage: ViewModifier {
  let active: Bool
  var covered = false
  func body(content: Content) -> some View {
    let interactive = active && !covered
    content
      .environment(\.musicPageIsActive, interactive)
      // A fading player reveals the selected page underneath. Coverage changes
      // interaction, never the page's pixels or identity.
      .opacity(active ? 1 : 0)
      .allowsHitTesting(interactive)
      .accessibilityHidden(!interactive)
      .disabled(!active)
  }
}
