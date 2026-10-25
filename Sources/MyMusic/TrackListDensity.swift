import AppKit
import MusicCore

/// One preference for song tables; queues keep their independent two-line layout.
enum TrackListDensity: String, CaseIterable, Identifiable {
  case standard, compact
  static let preferenceKey = "trackListDensity"
  var id: String { rawValue }
  var name: String { L10n.text(self == .standard ? "标准" : "紧凑") }
  var rowHeight: CGFloat { self == .standard ? 32 : 26 }
  var artworkSize: CGFloat { self == .standard ? 24 : 18 }
  var contentHeight: CGFloat { rowHeight - 8 }
  static func prepareForChange() {
    NotificationCenter.default.post(name: .trackListDensityWillChange, object: nil)
  }
}

extension Notification.Name {
  static let trackListDensityWillChange = Notification.Name("MyMusic.trackListDensityWillChange")
}
