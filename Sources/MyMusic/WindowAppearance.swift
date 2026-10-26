import AppKit
import MusicCore
import SwiftUI

enum MusicSurface {
  static let navigationMaterial = Material.regular
  static let content = NSColor(name: nil) { appearance in
    var color = NSColor.white
    appearance.performAsCurrentDrawingAppearance {
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .darkGray
      }
    }
    return color
  }
  static let sidebar = NSColor.windowBackgroundColor
  static let toolbar = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(srgbRed: 0.14, green: 0.17, blue: 0.19, alpha: 0.96)
      : NSColor.white.withAlphaComponent(0.96)
  }
  static let sidebarSelection = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor.white.withAlphaComponent(0.13)
      : NSColor.black.withAlphaComponent(0.075)
  }

}

enum MusicAppearance: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: String { rawValue }
  var name: String {
    switch self {
    case .system: return L10n.text("跟随系统")
    case .light: return L10n.text("亮色")
    case .dark: return L10n.text("深色")
    }
  }
  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
  func apply() {
    switch self {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    // Native windows must inherit the application again after a manual override.
    // One appearance owner keeps SwiftUI, materials and AppKit-painted dividers in sync.
    for window in NSApp.windows { window.appearance = nil }
  }
}

struct HideWindowToolbarTitle: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 15, *) {
      content.toolbar(removing: .title)
    } else {
      content
    }
  }
}

/// Draw only behind this column's toolbar, without covering adjacent columns.
struct NavigationToolbarBackdrop: View {
  var body: some View {
    GeometryReader { geometry in
      Rectangle().fill(MusicSurface.navigationMaterial)
        // Equal tint strength keeps both appearances translucent; the light
        // base stays white without the former near-opaque white overlay.
        .overlay(Color(nsColor: MusicSurface.content).opacity(0.35))
        .frame(height: geometry.safeAreaInsets.top)
        .offset(y: -geometry.safeAreaInsets.top)
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}

struct SidebarArtworkSample: Equatable, Identifiable {
  let id: String
  let url: String?
  let frame: CGRect
}

struct SidebarArtworkPreference: PreferenceKey {
  static var defaultValue: [SidebarArtworkSample] = []
  static func reduce(value: inout [SidebarArtworkSample], nextValue: () -> [SidebarArtworkSample]) {
    value += nextValue()
  }
}

/// Scroll geometry updates only the backdrop, at a bounded rate; the window root
/// must not observe every moving cover and invalidate its retained pages.
@MainActor final class SidebarBackdropState: ObservableObject {
  @Published private(set) var samples: [SidebarArtworkSample] = []
  private var pending: [SidebarArtworkSample] = []
  private var update: DispatchWorkItem?

  func submit(_ value: [SidebarArtworkSample]) {
    pending = value
    guard update == nil, value != samples else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.update = nil
      if self.samples != self.pending { self.samples = self.pending }
    }
    update = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
  }
  deinit { update?.cancel() }
}

struct SidebarArtworkBackdrop: View {
  @Environment(\.locale) private var locale
  @ObservedObject var state: SidebarBackdropState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if reduceTransparency {
          Color(nsColor: MusicSurface.sidebar)
        } else {
          Rectangle().fill(MusicSurface.navigationMaterial)
        }
        if !reduceTransparency {
          // Only the leftmost visible covers contribute, at their actual scroll positions.
          let visible = state.samples.filter {
            $0.url != nil && $0.frame.minX < 40 && $0.frame.maxY > 0
              && $0.frame.minY < geometry.size.height
          }.sorted { $0.frame.minY < $1.frame.minY }.prefix(4)
          ForEach(Array(visible)) { sample in
            AsyncImage(url: URL(string: sample.url ?? "")) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              Color.clear
            }
            .frame(width: geometry.size.width * 1.6, height: max(180, sample.frame.height * 1.4))
            .clipped()
            .saturation(0.65)
            .blur(radius: 65)
            .opacity(colorScheme == .dark ? 0.15 : 0.09)
            .position(x: geometry.size.width * 1.20, y: sample.frame.midY)
          }
        }
      }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}

struct SidebarLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 10) {
      configuration.icon.foregroundStyle(MusicAccent.color).font(
        .system(size: 18, weight: .regular)
      )
      .frame(width: 20)
      configuration.title
    }.padding(.vertical, 2)
  }
}

/// Keep the native window controls, without a separate title strip or hard rule.
struct WindowChrome: NSViewRepresentable {
  @Environment(\.locale) private var locale
  func makeNSView(context: Context) -> ChromeView { ChromeView() }
  func updateNSView(_ nsView: ChromeView, context: Context) { nsView.scheduleScrollAppearance() }

  final class ChromeView: NSView {
    private var updates: NSObjectProtocol?
    private var scheduled = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let updates { NotificationCenter.default.removeObserver(updates) }
      updates = nil
      guard let window else { return }
      updates = NotificationCenter.default.addObserver(
        forName: NSWindow.didUpdateNotification, object: window, queue: .main
      ) { [weak self] _ in self?.scheduleScrollAppearance() }
      scheduleScrollAppearance()
      window.styleMask.insert(.fullSizeContentView)
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.backgroundColor = MusicSurface.content
      window.titlebarSeparatorStyle = .none
    }
    func scheduleScrollAppearance() {
      guard !scheduled, window != nil else { return }
      scheduled = true
      // Coalesce native view reconstruction, without publishing SwiftUI state or forcing layout.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
        guard let self else { return }
        self.scheduled = false
        if let root = self.window?.contentView { MusicScroller.applyTree(to: root) }
      }
    }
    deinit { if let updates { NotificationCenter.default.removeObserver(updates) } }
  }
}
