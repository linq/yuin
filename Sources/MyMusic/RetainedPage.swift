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
  func body(content: Content) -> some View {
    content
      .environment(\.musicPageIsActive, active)
      .opacity(active ? 1 : 0)
      .allowsHitTesting(active)
      .accessibilityHidden(!active)
      .disabled(!active)
  }
}
