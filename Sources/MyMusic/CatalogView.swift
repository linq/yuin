import MusicCore
import SwiftUI

enum CollectionAction: Equatable {
  case play, shuffle, playNext, enqueue, save
  case add(UUID)
  case download
}

struct CatalogView: View {
  @Environment(\.locale) private var locale
  enum Kind: String, CaseIterable {
    case search, playlists, charts
    var title: String {
      switch self {
      case .search: return L10n.text("搜索")
      case .playlists: return L10n.text("歌单")
      case .charts: return L10n.text("排行榜")
      }
    }
  }
  let kind: Kind
  var isActive = true
  var searchFocusRequest = 0
  var initialCollection: MusicCollection? = nil
  var navigateCollection: ((MusicCollection) -> Void)? = nil
  @EnvironmentObject var model: AppModel
  private var platform: MusicPlatform { model.state.selectedPlatform ?? .kw }
  @State private var query = ""
  @State private var submitted = ""
  @State private var tracks: [Track] = []
  @State private var collections: [MusicCollection] = []
  @State private var collection: MusicCollection?
  @State private var browsePage = 1
  @State private var trackPage = 1
  @State private var total = 0
  @State private var knownTotal = 0
  @State private var collectionTotal = 0
  @State private var hasMoreCollections = true
  @State private var busy = false
  @State private var browseError: String?
  @State private var trackError: String?
  @State private var task: Task<Void, Never>?
  @State private var generation = UUID()
  @State private var actionTask: Task<Void, Never>?
  @State private var actionGeneration = UUID()
  @State private var actionBusy = false
  @State private var actionCollectionKey: String?
  @State private var savedLists: [String: UUID] = [:]
  @State private var batchTracks: [Track] = []
  @State private var downloadSheet = false
  @State private var displayedPlatform: MusicPlatform?
  @State private var availableWidth: CGFloat = 1000
  @State private var gridScrollScope = NativeScrollScope()
  @State private var detailHeaderCollapsed = false
  @State private var gridWidth: CGFloat = 0
  @State private var selectedCollectionID: String?
  @FocusState private var gridFocused: Bool
  init(
    kind: Kind, isActive: Bool = true, searchFocusRequest: Int = 0,
    initialCollection: MusicCollection? = nil,
    navigateCollection: ((MusicCollection) -> Void)? = nil
  ) {
    self.kind = kind
    self.isActive = isActive
    self.searchFocusRequest = searchFocusRequest
    self.initialCollection = initialCollection
    self.navigateCollection = navigateCollection
    _collection = State(initialValue: initialCollection)
  }
  private var showingTracks: Bool { kind == .search || collection != nil }
  private var page: Int { showingTracks ? trackPage : browsePage }
  private var error: String? { showingTracks ? trackError : browseError }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        if kind != .search && initialCollection == nil {
          // Keep the grid mounted under the detail so Back restores the exact scroll offset.
          collectionGrid
            .opacity(collection == nil ? 1 : 0)
            .allowsHitTesting(collection == nil)
            .accessibilityHidden(collection != nil)
            .disabled(collection != nil)
        }
        if showingTracks {
          VStack(alignment: .leading, spacing: 12) {
            if let collection, tracks.isEmpty {
              collectionHeader(
                collection, artworkSize: min(180, max(120, geometry.size.height * 0.38)))
            }
            if let error, tracks.isEmpty { errorView(error) }
            trackResults(artworkSize: min(180, max(120, geometry.size.height * 0.38)))
          }
          .padding(.top, collection != nil && tracks.isEmpty ? 24 : 0)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: geometry.size.width, initial: true) { _, width in
          if abs(availableWidth - width) > 1 { availableWidth = width }
        }
    }
    .background {
      if isActive, showingTracks, !detailHeaderCollapsed {
        GeometryReader { geometry in
          Color.clear.preference(
            key: SidebarArtworkPreference.self,
            value: [
              SidebarArtworkSample(
                id: "catalog-header", url: collection?.artwork ?? tracks.first?.artwork,
                frame: CGRect(x: 0, y: 24, width: 180, height: min(250, geometry.size.height)))
            ])
        }
      }
    }
    .toolbar {
      if isActive {
        if kind == .search {
          ToolbarItem(id: "catalog-search", placement: .principal) { searchField }
        }
        if kind == .playlists && collection == nil {
          ToolbarItem(id: "playlist-search", placement: .primaryAction) {
            CatalogSearchField(
              text: $query, focusRequest: 0,
              placeholder: L10n.text("搜索歌单"), accessibilityName: L10n.text("搜索歌单"),
              focusesOnAppear: false, submit: search
            )
            .frame(width: min(360, max(220, availableWidth - 320)), height: 38)
          }
        }
        if let collection, detailHeaderCollapsed {
          ToolbarItem(id: "collapsed-collection", placement: .principal) {
            HStack(spacing: 8) {
              Artwork(url: collection.artwork, size: 26, radius: 4)
              Text(collection.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
              Button {
                fullCollection(collection, action: .play)
              } label: {
                MusicToolbarLabel(symbol: "play.fill")
              }.buttonStyle(.plain).disabled(actionBusy || tracks.isEmpty)
                .accessibilityLabel(L10n.text("播放"))
            }.frame(maxWidth: max(80, min(260, availableWidth - 600)))
          }
        }
        ToolbarItem(id: "catalog-platform-" + kind.rawValue, placement: .primaryAction) {
          if let collection {
            MusicToolbarLabel(symbol: "music.note", title: collection.platform.name)
              .foregroundStyle(.secondary)
          } else {
            platformPicker
          }
        }
      }
    }
    .task {
      guard displayedPlatform == nil else { return }
      displayedPlatform = platform
      if let initialCollection {
        open(initialCollection)
      } else if kind != .search {
        load(reset: true)
      }
    }
    .onChange(of: platform) { _, _ in
      if isActive && collection == nil { updatePlatform() }
    }
    .onChange(of: isActive) { _, active in
      if !active { cancelAction() }
      if active {
        // An open collection remains tied to its original platform until Back.
        if collection == nil && displayedPlatform != platform { updatePlatform() }
      }
    }
    .onDisappear {
      task?.cancel()
      generation = UUID()
      cancelAction()
    }
    .sheet(isPresented: $downloadSheet) { DownloadSheet(tracks: batchTracks) }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      CatalogSearchField(text: $query, focusRequest: searchFocusRequest, submit: search)
      if busy { ProgressView().controlSize(.mini) }
    }.frame(width: min(480, max(240, availableWidth - 320)), height: 38)
  }

  private var platformPicker: some View {
    Menu {
      Picker(
        L10n.text("音乐平台"),
        selection: Binding(
          get: { platform },
          set: {
            model.state.selectedPlatform = $0
            model.persist()
          }
        )
      ) {
        ForEach(MusicPlatform.allCases) { Text($0.name).tag($0) }
      }
    } label: {
      MusicToolbarLabel(symbol: "music.note", title: platform.name, disclosure: true)
    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .help(L10n.text("切换音乐平台")).accessibilityLabel(L10n.text("音乐平台：\(platform.name)"))
  }

  private var collectionGrid: some View {
    ScrollViewReader { gridProxy in
      ScrollView {
        VStack(spacing: 20) {
          if !submitted.isEmpty {
            HStack {
              Text(L10n.text("“\(submitted)”的歌单 · \(collections.count) / \(collectionTotal)"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
              Spacer()
              Button(L10n.text("返回推荐歌单")) {
                query = ""
                search()
              }.buttonStyle(.plain)
            }.padding(.horizontal, 32)
          }
          if let browseError { errorView(browseError) }
          CollectionGrid {
            ForEach(collections) { item in
              CollectionCard(
                collection: item, saved: isSaved(item), lists: model.state.playlists,
                busy: actionBusy && actionCollectionKey == collectionKey(item),
                actionsDisabled: actionBusy,
                keyboardSelected: gridFocused && selectedCollectionID == item.id,
                open: {
                  selectedCollectionID = item.id
                  if let navigateCollection { navigateCollection(item) } else { open(item) }
                },
                perform: { fullCollection(item, action: $0) }, cancel: cancelAction
              ).id(item.id)
                .background {
                  GeometryReader { geometry in
                    let frame = geometry.frame(in: .named("musicDetail"))
                    Color.clear.preference(
                      key: SidebarArtworkPreference.self,
                      value: isActive && collection == nil && frame.minX < 40
                        && frame.maxY > 0
                        ? [
                          SidebarArtworkSample(
                            id: item.id, url: item.artwork,
                            frame: CGRect(
                              x: frame.minX, y: (frame.minY / 24).rounded() * 24,
                              width: frame.width, height: frame.height))
                        ] : [])
                  }
                }
            }
          }.background {
            GeometryReader { geometry in
              Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in
                if abs(gridWidth - width) > 1 { gridWidth = width }
              }
            }
          }
          if busy && collection == nil { ProgressView().padding() }
          if kind == .playlists && !collections.isEmpty && hasMoreCollections {
            Text(busy ? L10n.text("正在载入…") : L10n.text("滚动到底部自动载入更多歌单"))
              .font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
          }
          if !busy && collections.isEmpty && browseError == nil {
            ContentUnavailableView(
              submitted.isEmpty ? L10n.text("没有可显示的内容") : L10n.text("没有找到相关歌单"),
              systemImage: "square.grid.2x2",
              description: Text(
                submitted.isEmpty ? L10n.text("此平台可能暂未提供可用的公开数据。") : L10n.text("试试其他关键词或音乐平台。")))
          }
        }.padding(.top, 28).padding(.bottom, 24)
          .accessibilityHidden(!isActive || collection != nil)
      }.scrollContentBackground(.hidden)
        .contentMargins(.bottom, FloatingPlayerOverlay.scrollClearance, for: .scrollContent)
        .background(NativeScrollBoundary(scope: gridScrollScope, isStart: true))
        .overlay(
          NativeScrollBoundary(scope: gridScrollScope, isStart: false).allowsHitTesting(false)
        )
        .modifier(CatalogScrollEdge())
        .background(
          NavigationToolbarScrollSource(
            scope: gridScrollScope, active: isActive && collection == nil)
        )
        .background(
          ScrollPositionMemory(
            active: isActive && collection == nil, scope: gridScrollScope,
            rowIDs: collections.map(\.id), contentCount: collections.count,
            loadMore: kind == .playlists && collection == nil && hasMoreCollections
              && !busy && browseError == nil && !collections.isEmpty
              ? { load(reset: false) } : nil)
        )
        .id("\(displayedPlatform?.rawValue ?? ""):\(submitted)")
        .focusable().focusEffectDisabled().focused($gridFocused)
        .onMoveCommand { direction in
          guard isActive, collection == nil, !collections.isEmpty else { return }
          let current = collections.firstIndex { $0.id == selectedCollectionID }
          let index = CollectionKeyboardNavigation.destination(
            current: current, count: collections.count,
            width: gridWidth > 0 ? gridWidth : availableWidth, direction: direction)
          selectedCollectionID = collections[index].id
          gridFocused = true
          gridProxy.scrollTo(collections[index].id)
        }
        .onKeyPress(.return) {
          guard gridFocused, let item = collections.first(where: { $0.id == selectedCollectionID })
          else { return .ignored }
          if let navigateCollection { navigateCollection(item) } else { open(item) }
          return .handled
        }
        .onChange(of: gridFocused) { _, focused in
          if focused && selectedCollectionID == nil { selectedCollectionID = collections.first?.id }
        }
        .onChange(of: isActive) { _, active in
          if active, selectedCollectionID != nil, collection == nil {
            DispatchQueue.main.async { gridFocused = true }
          }
        }
    }

  }

  private func collectionHeader(_ item: MusicCollection, artworkSize: CGFloat, inset: CGFloat = 32)
    -> some View
  {
    let saved = isSaved(item)
    let layout =
      availableWidth < 560
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 24))
    return layout {
      Artwork(url: item.artwork, size: artworkSize, radius: 9)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
      VStack(alignment: .leading, spacing: 10) {
        Text(item.title).font(.system(size: 23, weight: .bold)).lineLimit(2).help(item.title)
        Text(item.subtitle.isEmpty ? item.platform.name : item.subtitle)
          .font(.system(size: 14)).foregroundStyle(MusicAccent.color).lineLimit(1)
        Text(total > 0 ? L10n.text("\(total) 首歌曲 · \(item.platform.name)") : item.platform.name)
          .font(.system(size: 12)).foregroundStyle(.secondary)
        HStack(spacing: 10) {
          Button {
            fullCollection(item, action: .play)
          } label: {
            Label(L10n.text("播放"), systemImage: "play.fill")
          }.buttonStyle(MusicCollectionActionStyle(prominent: true))
          Button {
            fullCollection(item, action: .shuffle)
          } label: {
            Label(L10n.text("随机播放"), systemImage: "shuffle")
          }.buttonStyle(MusicCollectionActionStyle())
          Menu {
            Button(L10n.text("下一首播放")) { fullCollection(item, action: .playNext) }
            Button(L10n.text("添加到队尾")) { fullCollection(item, action: .enqueue) }
            Divider()
            Button(saved ? L10n.text("已添加到我的列表") : L10n.text("添加到我的列表")) {
              fullCollection(item, action: .save)
            }.disabled(saved)
            Menu(L10n.text("添加到已有列表")) {
              ForEach(model.state.playlists) { list in
                Button(list.name) { fullCollection(item, action: .add(list.id)) }
              }
            }.disabled(model.state.playlists.isEmpty)
            Button(L10n.text("下载整张列表…")) { fullCollection(item, action: .download) }
          } label: {
            MusicToolbarLabel(symbol: saved ? "checkmark.circle" : "ellipsis")
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(MusicAccent.color)
          .help(
            saved ? L10n.text("已添加 · 更多操作") : L10n.text("歌单操作")
          )
          .accessibilityLabel(saved ? L10n.text("已添加 · 歌单操作") : L10n.text("歌单操作"))
        }.controlSize(.regular).disabled(actionBusy || (tracks.isEmpty && busy))
        if actionBusy {
          HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(L10n.text("正在准备完整歌单…")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("取消"), action: cancelAction).buttonStyle(.plain).font(.caption)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.horizontal, inset).padding(.bottom, 8)
  }

  @ViewBuilder private func trackResults(artworkSize: CGFloat) -> some View {
    if tracks.isEmpty {
      if busy {
        ProgressView(L10n.text("正在获取歌曲…")).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if error == nil {
        ContentUnavailableView(
          submitted.isEmpty && kind == .search ? L10n.text("从一次搜索开始") : L10n.text("没有找到歌曲"),
          systemImage: "magnifyingglass",
          description: Text(
            submitted.isEmpty && kind == .search
              ? L10n.text("在顶部输入歌曲、歌手或专辑，按回车搜索。") : L10n.text("试试其他关键词或平台。"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Spacer()
      }
    } else {
      TracksView(
        tracks: tracks, ranked: collection?.isChart == true,
        searchContext: collection == nil
          ? .results : collection?.isChart == true ? .chart : .playlist,
        loadMore: tracks.count < total && !busy && trackError == nil
          ? { load(reset: false) } : nil,
        scrollHeader: collection.map {
          AnyView(collectionHeader($0, artworkSize: artworkSize, inset: 8).padding(.top, 24))
        }, headerCollapsed: { detailHeaderCollapsed = $0 }
      )
      .padding(.horizontal, 24)
      HStack {
        Text(L10n.text("已显示 \(tracks.count) / \(max(total, tracks.count)) 首"))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        if let trackError {
          Text(trackError).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(trackError)
          Button(L10n.text("重试")) { load(reset: false) }.disabled(busy)
        } else if tracks.count < total {
          if busy {
            ProgressView().controlSize(.mini)
            Text(L10n.text("正在载入…")).font(.caption).foregroundStyle(.secondary)
          } else {
            Text(L10n.text("滚动到底部自动载入")).font(.caption).foregroundStyle(.secondary)
          }
        }
      }.frame(height: 22).padding(.horizontal, 32).padding(.bottom, 10)
    }
  }

  private func errorView(_ message: String) -> some View {
    VStack(spacing: 8) {
      Label(L10n.text("暂时无法载入"), systemImage: "wifi.exclamationmark").font(.headline)
      Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button(L10n.text("重试")) { load(reset: page == 1) }
    }.frame(maxWidth: .infinity).padding(16)
      .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal, 32)
  }

  private func open(_ item: MusicCollection) {
    cancelAction()
    detailHeaderCollapsed = false
    collection = item
    total = 0
    load(reset: true)
  }

  private func updatePlatform() {
    displayedPlatform = platform
    task?.cancel()
    generation = UUID()
    cancelAction()
    busy = false
    detailHeaderCollapsed = false
    collection = nil
    tracks = []
    collections = []
    browsePage = 1
    trackPage = 1
    total = 0
    browseError = nil
    trackError = nil
    if kind != .search || !submitted.isEmpty { load(reset: true) }
  }

  private func search() {
    submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard kind == .playlists || !submitted.isEmpty else { return }
    load(reset: true)
  }

  private func load(reset: Bool) {
    task?.cancel()
    let token = UUID()
    generation = token
    let requested = reset ? 1 : page + 1
    let loadingTracks = showingTracks
    busy = true
    if loadingTracks {
      trackError = nil
      if reset {
        trackPage = 1
        tracks = []
        knownTotal = 0
        total = 0
      }
    } else {
      browseError = nil
      if reset {
        browsePage = 1
        collections = []
        collectionTotal = 0
        hasMoreCollections = true
      }
    }
    let selectedPlatform = platform
    let selectedCollection = collection
    let term = submitted
    task = Task {
      defer { if generation == token { busy = false } }
      do {
        if let selectedCollection {
          let result = try await model.catalog.tracks(in: selectedCollection, page: requested)
          guard generation == token, !Task.isCancelled else { return }
          let combined = dedup((reset ? [] : tracks) + result.tracks)
          if !reset && combined.count == tracks.count
            && combined.count < max(knownTotal, result.total)
          {
            throw MusicError.message(L10n.text("本页未返回更多歌曲，请稍后重试"))
          }
          tracks = combined
          knownTotal = max(knownTotal, result.total)
          total = max(knownTotal, tracks.count)
        } else if kind == .search {
          let result = try await model.catalog.search(
            term, platform: selectedPlatform, page: requested)
          guard generation == token, !Task.isCancelled else { return }
          let combined = dedup((reset ? [] : tracks) + result.tracks)
          if !reset && combined.count == tracks.count
            && combined.count < max(knownTotal, result.total)
          {
            throw MusicError.message(L10n.text("本页未返回更多歌曲，请稍后重试"))
          }
          tracks = combined
          knownTotal = max(knownTotal, result.total)
          total = max(knownTotal, tracks.count)
        } else {
          let result: [MusicCollection]
          var searchTotal: Int?
          if kind == .playlists && !term.isEmpty {
            let response = try await model.catalog.searchCollections(
              term, platform: selectedPlatform, page: requested)
            result = response.collections
            searchTotal = response.total
          } else {
            result = try await model.catalog.collections(
              platform: selectedPlatform, charts: kind == .charts, page: requested)
          }
          guard generation == token, !Task.isCancelled else { return }
          let previousCount = reset ? 0 : collections.count
          var seen = Set<String>()
          collections = ((reset ? [] : collections) + result).filter { seen.insert($0.id).inserted }
          collectionTotal = searchTotal ?? collections.count
          hasMoreCollections =
            collections.count > previousCount
            && (searchTotal.map { collections.count < $0 } ?? true)
        }
        if loadingTracks { trackPage = requested } else { browsePage = requested }
      } catch {
        if generation == token, !Task.isCancelled {
          if loadingTracks {
            trackError = error.localizedDescription
          } else {
            browseError = error.localizedDescription
          }
        }
      }
    }
  }

  private func collectionKey(_ item: MusicCollection) -> String {
    "\(item.platform.rawValue):\(item.isChart ? "chart" : "playlist"):\(item.id)"
  }
  private func isSaved(_ item: MusicCollection) -> Bool {
    savedLists[collectionKey(item)].map { id in model.state.playlists.contains { $0.id == id } }
      ?? false
  }

  private func cancelAction() {
    actionTask?.cancel()
    actionGeneration = UUID()
    actionBusy = false
    actionCollectionKey = nil
  }

  private func fullCollection(_ item: MusicCollection, action: CollectionAction) {
    cancelAction()
    let token = UUID()
    actionGeneration = token
    actionBusy = true
    actionCollectionKey = collectionKey(item)
    actionTask = Task {
      defer {
        if actionGeneration == token {
          actionBusy = false
          actionCollectionKey = nil
        }
      }
      do {
        // A complete, already loaded detail can be used immediately; otherwise fetch all pages.
        let all: [Track]
        if collection.map(collectionKey) == collectionKey(item) && knownTotal > 0
          && tracks.count >= knownTotal
        {
          all = tracks
        } else {
          all = try await model.catalog.allTracks(in: item)
        }
        guard actionGeneration == token, !Task.isCancelled else { return }
        guard !all.isEmpty else { throw MusicError.message(L10n.text("这张歌单暂无可用歌曲")) }
        switch action {
        case .play, .shuffle:
          model.state.queue.mode = action == .shuffle ? .shuffle : .sequential
          let first = action == .shuffle ? (all.randomElement() ?? all[0]) : all[0]
          model.play(first, in: all)
        case .playNext:
          model.enqueue(all, next: true)
        case .enqueue:
          model.enqueue(all, next: false)
        case .add(let id):
          guard model.state.playlists.contains(where: { $0.id == id }) else {
            throw MusicError.message(L10n.text("目标列表已删除"))
          }
          model.add(all, to: id)
        case .save:
          savedLists[collectionKey(item)] = model.createPlaylist(
            item.title, tracks: all)
        case .download:
          batchTracks = all
          downloadSheet = true
        }
      } catch {
        if actionGeneration == token, !Task.isCancelled {
          model.message = error.localizedDescription
        }
      }
    }
  }

  private func dedup(_ tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { seen.insert($0.id).inserted }
  }
}

private struct CatalogScrollEdge: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      content
    }
  }
}

struct CollectionCard: View {
  @Environment(\.locale) private var locale
  let collection: MusicCollection
  let saved: Bool
  let lists: [LocalPlaylist]
  let busy: Bool
  let actionsDisabled: Bool
  var keyboardSelected = false
  let open: () -> Void
  let perform: (CollectionAction) -> Void
  let cancel: () -> Void
  @State private var hovered = false
  @FocusState private var focus: Control?
  private enum Control: Hashable { case open, play, more }
  private var revealsControls: Bool { hovered || focus != nil || busy }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .bottom) {
        Button(action: open) {
          GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
              Artwork(url: collection.artwork, size: geometry.size.width, radius: 8)
              if collection.isChart && (collection.artwork ?? "").isEmpty {
                Text(collection.title).font(.system(size: 22, weight: .semibold))
                  .foregroundStyle(MusicAccent.color).padding(14)
              }
            }
          }.aspectRatio(1, contentMode: .fit)
        }.buttonStyle(.plain).focused($focus, equals: .open)
          .accessibilityLabel(L10n.text("打开\(collection.title)"))
          .accessibilityAction(named: Text(L10n.text("播放整张列表"))) {
            if !actionsDisabled { perform(.play) }
          }
        LinearGradient(
          colors: [.clear, .black.opacity(0.48)], startPoint: .center, endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(revealsControls ? 1 : 0).allowsHitTesting(false)
        HStack {
          if busy {
            Button(action: cancel) {
              ZStack {
                ProgressView().controlSize(.small)
                Image(systemName: "xmark").font(.system(size: 8))
              }
              .frame(width: 32, height: 32).background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain).help(L10n.text("取消准备歌单")).accessibilityLabel(
              L10n.text("取消准备\(collection.title)"))
          } else {
            Button {
              perform(.play)
            } label: {
              Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32).background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain).focused($focus, equals: .play).disabled(actionsDisabled)
              .help(L10n.text("播放\(collection.title)")).accessibilityLabel(
                L10n.text("播放\(collection.title)"))
          }
          Spacer()
          Menu {
            menu
          } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
              .frame(width: 30, height: 30).background(.regularMaterial, in: Circle())
          }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .focused($focus, equals: .more).tint(.primary)
            .accessibilityLabel(L10n.text("\(collection.title)的操作")).help(L10n.text("歌单操作"))
        }.padding(12).opacity(revealsControls ? 1 : 0).allowsHitTesting(revealsControls)
      }.aspectRatio(1, contentMode: .fit)
        .overlay {
          RoundedRectangle(cornerRadius: 8).strokeBorder(
            MusicAccent.color.opacity(keyboardSelected || focus != nil ? 1 : 0), lineWidth: 3
          )
          .allowsHitTesting(false)
        }
      Button(action: open) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(collection.title).font(.system(size: 13)).lineLimit(2)
            if saved {
              Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
            }
          }
          Text(collection.subtitle.isEmpty ? collection.platform.name : collection.subtitle)
            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.buttonStyle(.plain)
    }.contentShape(Rectangle()).help(collection.title)
      .onHover { hovered = $0 }.contextMenu { menu }
      .animation(.easeOut(duration: 0.15), value: revealsControls)
  }
  @ViewBuilder private var menu: some View {
    Button(L10n.text("打开详情"), action: open)
    Divider()
    Group {
      Button(L10n.text("播放")) { perform(.play) }
      Button(L10n.text("随机播放")) { perform(.shuffle) }
      Button(L10n.text("下一首播放")) { perform(.playNext) }
      Button(L10n.text("添加到队尾")) { perform(.enqueue) }
      Divider()
      Button(saved ? L10n.text("已保存到我的列表") : L10n.text("保存为我的列表")) { perform(.save) }.disabled(
        saved)
      Menu(L10n.text("添加到已有列表")) {
        ForEach(lists) { list in Button(list.name) { perform(.add(list.id)) } }
      }.disabled(lists.isEmpty)
      Button(L10n.text("下载整张列表…")) { perform(.download) }
    }.disabled(actionsDisabled)
    if busy {
      Divider()
      Button(L10n.text("取消准备"), action: cancel)
    }
  }
}

enum CollectionKeyboardNavigation {
  static func destination(
    current: Int?, count: Int, width: CGFloat, direction: MoveCommandDirection
  ) -> Int {
    guard count > 0, let current else { return 0 }
    let columns = max(1, Int((max(0, width - 64) + 20) / 175))
    let delta: Int
    switch direction {
    case .left: delta = -1
    case .right: delta = 1
    case .up: delta = -columns
    case .down: delta = columns
    @unknown default: delta = 0
    }
    return min(count - 1, max(0, current + delta))
  }
}
