import MusicCore
import SwiftUI

/// Shared target size for toolbar actions and menus in every music table.
struct MusicToolbarLabel: View {
  let symbol: String
  var title: String? = nil
  var disclosure = false
  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium))
      if let title { Text(title).font(.system(size: 13)).lineLimit(1) }
      if disclosure { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
    }
    .padding(.horizontal, title == nil ? 0 : 12)
    .frame(minWidth: 34, minHeight: 34)
    .background(.primary.opacity(0.05), in: Capsule())
    .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
    .contentShape(Capsule())
  }
}

enum TrackSearchContext {
  case playlist, chart, history, list, results
  var placeholder: String {
    switch self {
    case .playlist: return L10n.text("在歌单中查找")
    case .chart: return L10n.text("在排行榜中查找")
    case .history: return L10n.text("在最近播放中查找")
    case .list: return L10n.text("在列表中查找")
    case .results: return L10n.text("在搜索结果中查找")
    }
  }
}
