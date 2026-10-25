import MusicCore

struct MusicLocation: Identifiable, Hashable {
  let section: String
  var collection: MusicCollection? = nil
  var id: String {
    guard let collection else { return section }
    return "\(section):\(collection.platform.rawValue):\(collection.id)"
  }
  var catalog: CatalogView.Kind? { CatalogView.Kind(rawValue: section) }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A location owns its retained view, so Back/Forward never recreates results or selection.
struct BrowserNavigationHistory {
  private(set) var locations = [MusicLocation(section: "playlists")]
  private(set) var index = 0
  private(set) var visited = [MusicLocation(section: "playlists")]
  var current: MusicLocation { locations[index] }
  var canGoBack: Bool { index > 0 }
  var canGoForward: Bool { index + 1 < locations.count }
  mutating func visit(_ location: MusicLocation) {
    guard location != current else { return }
    locations = Array(locations.prefix(index + 1))
    locations.append(location)
    if locations.count > 80 { locations.removeFirst() }
    index = locations.count - 1
    if !visited.contains(location) { visited.append(location) }
    // Keep the three catalog roots, plus every location still reachable from history.
    visited.removeAll { $0.collection != nil && !locations.contains($0) }
  }
  mutating func back() { if canGoBack { index -= 1 } }
  mutating func forward() { if canGoForward { index += 1 } }
  mutating func removeMissingLists(valid: Set<String>) {
    let selected = current
    let validLocation: (MusicLocation) -> Bool = {
      !$0.section.hasPrefix("list:") || valid.contains($0.section)
    }
    locations = locations.filter(validLocation)
    visited = visited.filter(validLocation)
    if locations.isEmpty { locations = [MusicLocation(section: "history")] }
    index = locations.firstIndex(of: selected) ?? min(index, locations.count - 1)
    if !visited.contains(current) { visited.append(current) }
  }
}
