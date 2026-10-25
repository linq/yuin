import MusicCore
import SwiftUI

struct TracksView: View {
  @Environment(\.locale) private var locale
  @Environment(\.musicPageIsActive) private var isActive
  @EnvironmentObject var model: AppModel
  let tracks: [Track]
  var ranked = false
  var searchContext: TrackSearchContext = .list
  @AppStorage(TrackListDensity.preferenceKey) private var density: TrackListDensity = .standard
  var loadMore: (() -> Void)? = nil
  var remove: (([Track]) -> Void)? = nil
  var scrollHeader: AnyView? = nil
  var headerCollapsed: (Bool) -> Void = { _ in }
  @State private var scrollScope = NativeScrollScope()
  @State private var selection = Set<String>()
  @State private var downloadTracks: [Track] = []
  @State private var showDownload = false
  @State private var filter = ""
  @State private var order = TrackDisplayOrder.original
  @State private var filterPopover = false
  @State private var availableWidth: CGFloat = 768
  private var visibleTracks: [Track] {
    TrackPresentation.tracks(tracks, matching: filter, order: order)
  }
  private var ranks: [String: Int] {
    Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($0.element.id, $0.offset + 1) })
  }
  private func selected(_ ids: Set<String>) -> [Track] {
    visibleTracks.filter { ids.contains($0.id) }
  }
  var body: some View {
    let displayedTracks = visibleTracks
    let rankByID = ranked ? ranks : [:]
    let currentID = model.current?.id
    return VStack(spacing: 0) {
      Table(displayedTracks, selection: $selection) {
        TableColumn(L10n.text("歌曲")) { track in
          HStack(spacing: 8) {
            if ranked {
              Text("\(rankByID[track.id] ?? 0)").font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
            }
            ZStack {
              Artwork(url: track.artwork, size: density.artworkSize, radius: 3)
              if currentID == track.id {
                RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.65))
                PlaybackStateIcon(isLoading: model.isLoadingAudio, isPlaying: model.isPlaying)
              }
            }.frame(width: density.artworkSize, height: density.artworkSize)
            Text(track.title).fontWeight(currentID == track.id ? .semibold : .regular)
              .foregroundStyle(
                selection.contains(track.id)
                  ? Color.white : currentID == track.id ? Color.pink : Color.primary
              )
              .lineLimit(1).help(track.title)
            if model.offlineURL(track) != nil {
              Image(systemName: "arrow.down.circle.fill").font(.system(size: 10)).foregroundStyle(
                .secondary)
            }
          }.frame(height: density.contentHeight)
        }.width(min: 120, ideal: 320)
        TableColumn(L10n.text("艺人")) {
          Text($0.artist).lineLimit(1).foregroundStyle(
            selection.contains($0.id) ? Color.white.opacity(0.9) : Color.secondary
          ).help($0.artist)
        }
        .width(min: 70, ideal: 150)
        TableColumn(L10n.text("专辑")) {
          Text($0.album).lineLimit(1).foregroundStyle(
            selection.contains($0.id) ? Color.white.opacity(0.9) : Color.secondary
          ).help($0.album)
        }
        .width(min: 90, ideal: 180)
        TableColumn(L10n.text("时长")) {
          Text(Track.time($0.duration)).monospacedDigit().foregroundStyle(
            selection.contains($0.id) ? Color.white.opacity(0.9) : Color.secondary)
        }.width(45)
        TableColumn("") { track in
          Menu {
            TrackMenu(
              track: track, play: { model.play(track, in: displayedTracks) },
              download: {
                downloadTracks = [track]
                showDownload = true
              })
          } label: {
            Image(systemName: "ellipsis").foregroundStyle(
              selection.contains(track.id) ? Color.white : Color.secondary)
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.secondary).frame(width: 20)
          .accessibilityLabel(L10n.text("\(track.title)的操作"))
        }.width(24)
      }
      // Keep SwiftUI's own configuration consistent with the native appearance.
      // Otherwise every selection update briefly restores alternating backgrounds.
      .alternatingRowBackgrounds(.disabled)
      .background(NativeScrollBoundary(scope: scrollScope, isStart: true))
      .overlay(NativeScrollBoundary(scope: scrollScope, isStart: false).allowsHitTesting(false))
      .background(TrackTableAppearance(selection: selection, scope: scrollScope, density: density))
      .background {
        if let scrollHeader {
          CollectionScrollHeader(
            content: AnyView(
              scrollHeader.padding(.bottom, 8).environment(\.locale, locale).environmentObject(
                model)
            ), active: isActive, scope: scrollScope, collapsed: headerCollapsed)
        }
      }
      .background(
        ScrollPositionMemory(
          active: isActive, table: true, scope: scrollScope, layoutKey: density.rawValue,
          rowIDs: displayedTracks.map(\.id), contentCount: tracks.count,
          loadMore: filter.isEmpty ? loadMore : nil)
      )
      .accessibilityHidden(!isActive)
      .font(.system(size: 12)).controlSize(.small)
      .overlay {
        if displayedTracks.isEmpty { Text(L10n.text("没有匹配的歌曲")).foregroundStyle(.secondary) }
      }
      .contextMenu(forSelectionType: String.self) { ids in
        let songs = selected(ids)
        if let first = songs.first {
          Button(L10n.text("播放")) { model.play(first, in: displayedTracks) }
          Button(L10n.text("下一首播放")) { model.enqueue(songs, next: true) }
          Button(L10n.text("添加到队尾")) { model.enqueue(songs, next: false) }
          Menu(L10n.text("添加到列表")) {
            ForEach(model.state.playlists) { list in
              Button(list.name) { model.add(songs, to: list.id) }
            }
            Button(L10n.text("新建列表…")) { model.createPlaylist(L10n.text("新建列表"), tracks: songs) }
          }
          Button(L10n.text("下载所选 \(songs.count) 首…")) {
            downloadTracks = songs
            showDownload = true
          }
          if let remove {
            Divider()
            Button(L10n.text("从此列表移除"), role: .destructive) { remove(songs) }
          }
        }
      } primaryAction: { ids in
        if let track = selected(ids).first { model.play(track, in: displayedTracks) }
      }
    }
    .background {
      GeometryReader { geometry in
        Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in
          if abs(availableWidth - width) > 1 { availableWidth = width }
        }
      }
    }
    .toolbar {
      if isActive {
        ToolbarItem(id: "song-table-options", placement: .primaryAction) { optionsMenu }
        ToolbarItem(id: "song-table-find", placement: .primaryAction) {
          if searchContext == .results || availableWidth < 500 {
            Button {
              filterPopover.toggle()
            } label: {
              MusicToolbarLabel(
                symbol: filter.isEmpty
                  ? "magnifyingglass" : "line.3.horizontal.decrease.circle.fill")
            }
            .buttonStyle(.plain).help(searchContext.placeholder)
            .accessibilityLabel(searchContext.placeholder)
            .popover(isPresented: $filterPopover) {
              VStack(alignment: .leading, spacing: 10) {
                Text(searchContext.placeholder).font(.headline)
                localSearch(focus: true).frame(width: 280, height: 38)
                Text(L10n.text("\(visibleTracks.count) / \(tracks.count) 首歌曲"))
                  .font(.caption).foregroundStyle(.secondary)
              }.padding(16)
            }
          } else {
            localSearch(focus: false).frame(
              width: min(280, max(180, availableWidth - 480)), height: 38)
          }
        }
      }
    }
    .onChange(of: filter) { _, _ in selection.formIntersection(Set(displayedTracks.map(\.id))) }
    .onChange(of: tracks.map(\.id)) { _, ids in selection.formIntersection(Set(ids)) }
    .sheet(isPresented: $showDownload) { DownloadSheet(tracks: downloadTracks) }
  }
  private func localSearch(focus: Bool) -> some View {
    CatalogSearchField(
      text: $filter, focusRequest: 0, placeholder: searchContext.placeholder,
      accessibilityName: searchContext.placeholder, focusesOnAppear: focus, submit: {}
    )
    .help(L10n.text("仅查找已载入的歌曲"))
  }
  private var optionsMenu: some View {
    Menu {
      Text(L10n.text("\(visibleTracks.count) / \(tracks.count) 首歌曲"))
      Picker(L10n.text("排序"), selection: $order) {
        ForEach(TrackDisplayOrder.allCases, id: \.self) { Text($0.name).tag($0) }
      }
      Divider()
      Picker(
        L10n.text("歌曲列表密度"),
        selection: Binding(
          get: { density },
          set: {
            guard density != $0 else { return }
            TrackListDensity.prepareForChange()
            density = $0
          })
      ) {
        ForEach(TrackListDensity.allCases) { Text($0.name).tag($0) }
      }
    } label: {
      MusicToolbarLabel(symbol: "line.3.horizontal.decrease")
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .help(ranked ? L10n.text("调整显示顺序，保留原始榜单名次") : L10n.text("调整显示顺序"))
    .accessibilityLabel(L10n.text("排序与显示选项"))
  }

}
struct TrackMenu: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  let track: Track
  let play: () -> Void
  let download: () -> Void
  var body: some View {
    Button(L10n.text("播放"), action: play)
    Button(L10n.text("下一首播放")) { model.enqueue(track, next: true) }
    Button(L10n.text("添加到队尾")) { model.enqueue(track, next: false) }
    Button(L10n.text("喜欢")) { model.favorite(track) }
    Menu(L10n.text("添加到列表")) {
      ForEach(model.state.playlists) { list in Button(list.name) { model.add([track], to: list.id) }
      }
    }
    Button(L10n.text("下载…"), action: download)
  }
}
struct TrackLibraryView: View {
  @Environment(\.locale) private var locale
  @Environment(\.musicPageIsActive) private var isActive
  let tracks: [Track]
  @EnvironmentObject var model: AppModel
  @State private var download = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if tracks.isEmpty {
        ContentUnavailableView(
          L10n.text("还没有歌曲"), systemImage: "music.note",
          description: Text(L10n.text("搜索并播放喜欢的音乐，开始建立你的资料库。"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        TracksView(tracks: tracks, searchContext: .history).padding(.horizontal, 24)
      }
    }.toolbar {
      if isActive {
        ToolbarItem(placement: .principal) {
          Text(L10n.text("\(tracks.count) 首歌曲")).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            if let first = tracks.first { model.play(first, in: tracks) }
          } label: {
            MusicToolbarLabel(symbol: "play.fill")
          }
          .buttonStyle(.plain).help(L10n.text("全部播放")).accessibilityLabel(L10n.text("全部播放"))
          .disabled(tracks.isEmpty)
          Menu {
            Button(L10n.text("全部下载…")) { download = true }
          } label: {
            MusicToolbarLabel(symbol: "ellipsis")
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .accessibilityLabel(L10n.text("更多操作")).disabled(tracks.isEmpty)
        }
      }
    }.sheet(isPresented: $download) { DownloadSheet(tracks: tracks) }
  }
}
struct PlaylistView: View {
  @Environment(\.locale) private var locale
  @Environment(\.musicPageIsActive) private var isActive
  @EnvironmentObject var model: AppModel
  let id: UUID
  @State private var rename = false
  @State private var name = ""
  @State private var delete = false
  @State private var download = false
  private var list: LocalPlaylist? { model.state.playlists.first { $0.id == id } }
  var body: some View {
    if let list {
      GeometryReader { geometry in
        VStack(spacing: 12) {
          HStack(spacing: 24) {
            Artwork(
              url: list.tracks.first?.artwork,
              size: min(180, max(120, geometry.size.height * 0.38)), radius: 9
            )
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 12) {
              Text(list.name).font(.system(size: 23, weight: .bold)).lineLimit(2).help(list.name)
              Text(L10n.text("\(list.tracks.count) 首歌曲 · 我的列表")).font(.system(size: 12))
                .foregroundStyle(
                  .secondary)
              HStack(spacing: 10) {
                Button {
                  if let first = list.tracks.first {
                    model.state.queue.mode = .sequential
                    model.play(first, in: list.tracks)
                  }
                } label: {
                  Label(L10n.text("播放"), systemImage: "play.fill")
                }.buttonStyle(.borderedProminent).disabled(list.tracks.isEmpty)
                Button {
                  if let first = list.tracks.randomElement() {
                    model.state.queue.mode = .shuffle
                    model.play(first, in: list.tracks)
                  }
                } label: {
                  Label(L10n.text("随机播放"), systemImage: "shuffle")
                }
                .buttonStyle(.bordered).disabled(list.tracks.isEmpty)
                Menu {
                  Button(L10n.text("下一首播放")) { model.enqueue(list.tracks, next: true) }.disabled(
                    list.tracks.isEmpty)
                  Button(L10n.text("添加到队尾")) { model.enqueue(list.tracks, next: false) }.disabled(
                    list.tracks.isEmpty)
                  Button(L10n.text("下载全部…")) { download = true }.disabled(list.tracks.isEmpty)
                  Divider()
                  Button(L10n.text("重命名…")) {
                    name = list.name
                    rename = true
                  }
                  Button(L10n.text("删除列表…"), role: .destructive) { delete = true }
                } label: {
                  Image(systemName: "ellipsis")
                }.menuIndicator(.hidden).fixedSize().help(L10n.text("列表操作")).accessibilityLabel(
                  L10n.text("列表操作"))
              }.controlSize(.regular)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 8)
          if list.tracks.isEmpty {
            ContentUnavailableView(
              L10n.text("把喜欢的音乐放在这里"), systemImage: "music.note.list",
              description: Text(L10n.text("在歌曲菜单中选择“添加到列表”，或保存整张歌单。"))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            TracksView(
              tracks: list.tracks,
              remove: { songs in
                guard let i = model.state.playlists.firstIndex(where: { $0.id == id }) else {
                  return
                }
                let ids = Set(songs.map(\.id))
                model.state.playlists[i].tracks.removeAll { ids.contains($0.id) }
                model.persist()
              }
            ).padding(.horizontal, 24)
          }
        }
      }
      .background {
        if isActive {
          Color.clear.preference(
            key: SidebarArtworkPreference.self,
            value: [
              SidebarArtworkSample(
                id: "local-list-\(id)", url: list.tracks.first?.artwork,
                frame: CGRect(x: 0, y: 24, width: 180, height: 250))
            ])
        }
      }
      .alert(L10n.text("重命名列表"), isPresented: $rename) {
        TextField(L10n.text("名称"), text: $name)
        Button(L10n.text("取消"), role: .cancel) {}
        Button(L10n.text("保存")) {
          if let i = model.state.playlists.firstIndex(where: { $0.id == id }),
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            model.state.playlists[i].name = name
            model.persist()
          }
        }
      }
      .alert(L10n.text("删除“\(list.name)”？"), isPresented: $delete) {
        Button(L10n.text("取消"), role: .cancel) {}
        Button(L10n.text("删除"), role: .destructive) {
          model.state.playlists.removeAll { $0.id == id }
          model.persist()
        }
      } message: {
        Text(L10n.text("仅删除此列表，已下载的音频文件会保留。"))
      }
      .sheet(isPresented: $download) { DownloadSheet(tracks: list.tracks) }
    }
  }
}
