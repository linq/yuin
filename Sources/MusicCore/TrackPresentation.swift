import Foundation

public enum TrackDisplayOrder: String, CaseIterable {
  case original, title, artist, album, duration
  public var name: String {
    switch self {
    case .original: return L10n.text("原始顺序")
    case .title: return L10n.text("歌曲名称")
    case .artist: return L10n.text("艺人名称")
    case .album: return L10n.text("专辑名称")
    case .duration: return L10n.text("时长")
    }
  }
}

public enum TrackPresentation {
  public static func tracks(_ tracks: [Track], matching query: String, order: TrackDisplayOrder)
    -> [Track]
  {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = tracks.enumerated().filter { _, track in
      query.isEmpty
        || [track.title, track.artist, track.album].contains { $0.localizedStandardContains(query) }
    }
    guard order != .original else { return filtered.map(\.element) }
    return filtered.sorted { left, right in
      if order == .duration {
        return left.element.duration == right.element.duration
          ? left.offset < right.offset : left.element.duration < right.element.duration
      }
      func key(_ track: Track) -> String {
        switch order {
        case .artist: return track.artist
        case .album: return track.album
        default: return track.title
        }
      }
      let result = key(left.element).localizedStandardCompare(key(right.element))
      return result == .orderedSame ? left.offset < right.offset : result == .orderedAscending
    }.map(\.element)
  }
}
